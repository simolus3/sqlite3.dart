import 'dart:async';
import 'dart:collection';

import 'pool.dart';

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

/// A fair async semaphore implementation that manages a pool of resources and
/// allows giving out more than one resource at a time.
final class MultiSemaphore<T> {
  final Queue<T> _available;
  final Queue<_MultiSemaphoreWaiter<T>> _waiters = Queue();
  int _poolSize = 0;

  MultiSemaphore(Iterable<T> elements) : _available = ListQueue.of(elements) {
    _poolSize = _available.length;
  }

  int get poolSize => _poolSize;

  Future<R> withPermits<R>(
    int amount,
    FutureOr<R> Function(List<T>) action, {
    Future<void>? abort,
  }) {
    if (amount <= 0) {
      throw RangeError.value(amount, 'amount', 'Must be positive');
    }

    void markCompleted(List<T> acquired) {
      for (final element in acquired) {
        // Give to waiter, if possible
        if (_waiters.isNotEmpty) {
          final first = _waiters.first;
          assert(first.remaining > 0);
          first.acquiredItems.add(element);
          if (--first.remaining == 0) {
            _waiters.removeFirst();
            first.onAcquireComplete();
          }
        } else {
          // otherwise return to pool
          _available.addLast(element);
        }
      }
    }

    if (_available.length >= amount) {
      // We only add waiters when a call to withPermits drains the available
      // queue, and we give returned leases to waiters before adding it back
      // to the available queue. So if there are any available items at all, we
      // can't have an outstanding waiter.
      assert(_waiters.isEmpty);
      final acquired = List.generate(
        amount,
        (_) => _available.removeFirst(),
        growable: false,
      );
      return Future.sync(
        () => action(acquired),
      ).whenComplete(() => markCompleted(acquired));
    } else {
      final completer = Completer<R>.sync();
      late final _MultiSemaphoreWaiter<T> waiter;

      waiter = _MultiSemaphoreWaiter<T>(amount, () {
        completer.complete(Future.sync(() => action(waiter.acquiredItems)));
      });
      while (_available.isNotEmpty) {
        waiter.acquiredItems.add(_available.removeFirst());
        waiter.remaining--;
      }
      assert(waiter.remaining > 0);
      _waiters.add(waiter);

      abort?.whenComplete(() {
        if (!completer.isCompleted) {
          final didRemove = _waiters.remove(waiter);

          // The only way for waiters to get removed is for their callback to
          // get called, so we wouldn't enter this branch.
          assert(didRemove);
          completer.completeError(const PoolAbortException());
        }
      });
      return completer.future.whenComplete(
        () => markCompleted(waiter.acquiredItems),
      );
    }
  }
}

final class _MultiSemaphoreWaiter<T> {
  final List<T> acquiredItems = [];
  final void Function() onAcquireComplete;
  int remaining;

  _MultiSemaphoreWaiter(this.remaining, this.onAcquireComplete);
}
