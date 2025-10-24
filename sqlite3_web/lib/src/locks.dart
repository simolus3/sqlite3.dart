import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'types.dart';

@JS('navigator')
external Navigator get _navigator;

class WebLocks {
  final LockManager _lockManager;

  WebLocks._(this._lockManager);

  Future<HeldLock> request(String name, {AbortSignal? abortSignal}) {
    final gotLock = Completer<HeldLock>.sync();

    JSPromise callback(JSAny lock) {
      final completer = Completer<void>.sync();
      gotLock.complete(HeldLock._(completer));
      return completer.future.toJS;
    }

    final options = LockOptions();
    if (abortSignal case final signal?) {
      options.signal = signal;
    }

    _lockManager.request(name, options, callback.toJS).toDart.onError((e, s) {
      final domError = e as DOMException;

      if (!gotLock.isCompleted) {
        if (domError.name == 'AbortError') {
          gotLock.completeError(AbortException(), s);
        } else {
          gotLock.completeError(domError, s);
        }
      }

      return null;
    });
    return gotLock.future;
  }

  static WebLocks? instance =
      (_navigator as JSObject).hasProperty('locks'.toJS).toDart
          ? WebLocks._(_navigator.locks)
          : null;
}

class HeldLock {
  final Completer<void> _completer;

  HeldLock._(this._completer);

  void release() => _completer.complete();
}

final class DatabaseLocks {
  final String lockName;
  final Mutex _dartMutex = Mutex();

  /// Whether this database needs a lock implementation providing exclusive
  /// access across tabs.
  ///
  /// When a database is hosted by a shared worker, this is not necessary and
  /// we can use a Dart implementation with less overhead.
  /// For databases hosted on multiple dedicated workers, the navigator lock API
  /// is necessary to manage exclusive access.
  final bool needsInterContextLocks;

  DatabaseLocks(this.lockName, this.needsInterContextLocks);

  /// Returns whether a synchronous block could run immediately.
  ///
  /// This is the case if no inter-context locks are required and the local
  /// mutex is not currently held. Because the inner block would run
  /// synchronously, no concurrency is possible and we don't need to explicitly
  /// update the lock's state.
  bool get canRunSynchronousBlockDirectly {
    return !needsInterContextLocks && !_dartMutex._inCriticalSection;
  }

  Future<T> lock<T>(
      FutureOr<T> Function() criticalSection, AbortSignal? abortSignal) async {
    if (needsInterContextLocks) {
      final held =
          await WebLocks.instance!.request(lockName, abortSignal: abortSignal);
      return Future(criticalSection).whenComplete(held.release);
    }

    return _dartMutex.withCriticalSection(criticalSection, abort: abortSignal);
  }
}

/// A simple async mutex implemented in Dart.
final class Mutex {
  bool _inCriticalSection = false;
  final Queue<void Function()> _waiting = Queue();

  Future<T> withCriticalSection<T>(
    FutureOr<T> Function() action, {
    AbortSignal? abort,
  }) async {
    var holdsMutex = false;

    void markCompleted() {
      if (!holdsMutex) {
        return;
      }

      if (_waiting.isNotEmpty) {
        _waiting.removeFirst()();
      } else {
        _inCriticalSection = false;
      }
    }

    if (!_inCriticalSection) {
      assert(_waiting.isEmpty);
      _inCriticalSection = true;
      holdsMutex = true;
      return Future.sync(action).whenComplete(markCompleted);
    } else {
      assert(_inCriticalSection);
      final completer = Completer<T>.sync();

      void complete() {
        holdsMutex = true;
        completer.complete(Future.sync(action));
      }

      late StreamSubscription<void> abortSubscription;
      abortSubscription =
          EventStreamProviders.abortEvent.forTarget(abort).listen((_) {
        abortSubscription.cancel();

        if (!completer.isCompleted) {
          final didRemove = _waiting.remove(complete);

          // The only way for waiters to get removed is for [complete] to get
          // called, so we wouldn't enter this branch.
          assert(didRemove);
          completer.completeError(const AbortException());
        }
      });

      _waiting.addLast(complete);
      return completer.future.whenComplete(markCompleted);
    }
  }
}
