import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:meta/meta.dart';
import 'package:web/web.dart';

import 'external_locks_vfs.dart';
import 'types.dart';

@JS('navigator')
external Navigator get _navigator;

extension type WebLocks._(LockManager raw) {
  Future<HeldLock> request(
    String name, {
    AbortSignal? abortSignal,
    bool steal = false,
    void Function()? onStolen,
  }) {
    final gotLock = Completer<HeldLock>.sync();
    HeldLock? resolvedLock;

    JSPromise callback(JSAny lock) {
      final completer = Completer<void>.sync();
      gotLock.complete(resolvedLock = HeldLock._(completer));
      return completer.future.toJS;
    }

    final options = LockOptions(steal: steal);
    if (abortSignal case final signal?) {
      options.signal = signal;
    }

    raw.request(name, options, callback.toJS).toDart.onError((e, s) {
      final domError = e as DOMException;
      final isAbortError = domError.name == 'AbortError';

      if (resolvedLock case final resolved?) {
        if (!resolved._completer.isCompleted) {
          // The callback was invoked, but isn't completed yet. That can only
          // mean that the lock has been stolen from another tab.
          onStolen?.call();
        }
      } else {
        if (isAbortError) {
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

/// Locks to manage exclusive access to databases, across tabs if necessary.
///
/// This is especially relevant for OPFS databases, where we can't have more
/// than one tab operate on the database at the same time.
/// Additionally, we want to avoid lock overhead for single-tab apps. So, the
/// lock protocol is as follows:
///
///   1. Obtain an outer lock, stealing it if necessary.
///   2. Obtain an inner lock.
///   3. Run the exclusive operation.
///   4. Wait for another tab to steal the outer lock from us.
///   5. Return the inner lock.
final class DatabaseLocks {
  @visibleForTesting
  final String outerLockName;
  @visibleForTesting
  final String innerLockName;

  final Mutex _dartMutex = Mutex();

  /// Whether this database needs a lock implementation providing exclusive
  /// access across tabs.
  ///
  /// When a database is hosted by a shared worker, this is not necessary and
  /// we can use a Dart implementation with less overhead.
  /// For databases hosted on multiple dedicated workers, the navigator lock API
  /// is necessary to manage exclusive access.
  final bool needsInterContextLocks;

  /// If these locks are for a datbase backed by a VFS that needs to be locked
  /// and unlocked as well, a reference to that VFS.
  ExternalLocksState? _attachedVfs;

  (HeldLock, HeldLock)? _heldNavigatorLocks;

  DatabaseLocks(this.innerLockName, this.needsInterContextLocks)
    : outerLockName = '$innerLockName-outer';

  /// Returns whether a synchronous block could run immediately.
  ///
  /// This is the case if no inter-context locks are required and the local
  /// mutex is not currently held. Because the inner block would run
  /// synchronously, no concurrency is possible and we don't need to explicitly
  /// update the lock's state.
  bool get canRunSynchronousBlockDirectly {
    if (_dartMutex._inCriticalSection) return false;

    // We have no concurrent runner on the local mutex, so we can run a
    // synchronous block if concurrency from other tabs is not a concern or if
    // we currently hold an exclusive navigator lock (since we'd only return it
    // asynchronously, after a synchronous block ran).
    return !needsInterContextLocks || _heldNavigatorLocks != null;
  }

  Future<void> _acquireNavigatorLocks(AbortSignal? abortSignal) async {
    assert(_heldNavigatorLocks == null);
    final locks = WebLocks.instance!;
    HeldLock? outer, inner;

    try {
      // 1. Request the outer lock, stealing it from another tab if necessary.
      outer = await locks.request(
        outerLockName,
        steal: true,
        onStolen: _handleOuterLockStolen,
        // Not passing an abort signal here, those aren't supported with steal.
      );

      // 2. Obtain the inner lock.
      inner = await locks.request(innerLockName, abortSignal: abortSignal);

      await _attachedVfs?.markHasExclusiveAccess();
      _heldNavigatorLocks = (outer, inner);
    } on Object {
      // Failed to acquire some locks, ensure they're all released.
      outer?.release();
      inner?.release();
      rethrow;
    }
  }

  void attachVfs(ExternalLocksState state) {
    assert(_attachedVfs == null);
    assert(needsInterContextLocks);
    _attachedVfs = state;
  }

  void _handleOuterLockStolen() {
    // Step 4 and 5.
    releaseNavigatorLocks();
  }

  Future<T> lock<T>(
    FutureOr<T> Function() criticalSection,
    AbortSignal? abortSignal,
  ) {
    // Request the local mutex first. This is cheap, and allows
    // _withNavigatorLocks to assume exclusive access to inner state.
    return _dartMutex.withCriticalSection(abort: abortSignal, () {
      if (!needsInterContextLocks || _heldNavigatorLocks != null) {
        // Navigator locks not necessary or already held, run critical section
        // immediately.
        return criticalSection();
      }

      return _acquireNavigatorLocks(abortSignal).then((_) {
        // Step 3: Run the exclusive operation.
        return criticalSection();
        // Note: Step 4 and 5 run when the outer lock gets stolen from us, a
        // callback reacting to that would have been installed at this point.
      });
    });
  }

  Future<void> releaseNavigatorLocks() {
    return _dartMutex.withCriticalSection(() {
      if (_heldNavigatorLocks case (final outer, final inner)?) {
        _attachedVfs?.releaseExclusiveAccess();

        outer.release();
        inner.release();
        _heldNavigatorLocks = null;
      }
    });
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
    if (abort?.aborted == true) {
      throw const AbortException();
    }

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
      StreamSubscription<void>? abortSubscription;

      void complete() {
        holdsMutex = true;
        abortSubscription?.cancel();
        completer.complete(Future.sync(action));
      }

      if (abort != null) {
        abortSubscription = EventStreamProviders.abortEvent
            .forTarget(abort)
            .listen((_) {
              abortSubscription!.cancel();

              if (!completer.isCompleted) {
                final didRemove = _waiting.remove(complete);

                // The only way for waiters to get removed is for [complete] to
                // get called, so we wouldn't enter this branch.
                assert(didRemove);
                completer.completeError(const AbortException());
              }
            });
      }

      _waiting.addLast(complete);
      return completer.future.whenComplete(markCompleted);
    }
  }
}
