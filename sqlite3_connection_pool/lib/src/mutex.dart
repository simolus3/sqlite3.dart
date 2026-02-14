import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import 'abort_exception.dart';

/// An asynchronous mutex that allows aborting requests.
@internal
final class Mutex {
  bool _inCriticalSection = false;
  final Queue<void Function()> _waiting = Queue();

  Future<T> withCriticalSection<T>(
    FutureOr<T> Function() action, {
    Future<void>? abort,
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

      abort?.whenComplete(() {
        if (!completer.isCompleted) {
          final didRemove = _waiting.remove(complete);

          // The only way for waiters to get removed is for [complete] to get
          // called, so we wouldn't enter this branch.
          assert(didRemove);
          completer.completeError(const PoolAbortException());
        }
      });

      _waiting.addLast(complete);
      return completer.future.whenComplete(markCompleted);
    }
  }
}
