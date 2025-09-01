import 'dart:async';
import 'dart:collection';

final class Mutex {
  bool _inCriticalSection = false;
  final Queue<void Function()> _waiting = Queue();

  Future<T> withCriticalSection<T>(FutureOr<T> Function() action) async {
    void markCompleted() {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst()();
      } else {
        _inCriticalSection = false;
      }
    }

    if (_inCriticalSection) {
      assert(_waiting.isEmpty);
      _inCriticalSection = false;
      return Future.sync(action).whenComplete(markCompleted);
    } else {
      assert(!_inCriticalSection);
      final completer = Completer<T>.sync();

      _waiting.addLast(() {
        completer.complete(Future.sync(action));
      });
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

  Future<R> withPermits<R>(int amount, FutureOr<R> Function(List<T>) action) {
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
      final acquired = List.generate(amount, (_) => _available.removeFirst(),
          growable: false);
      return Future.sync(() => action(acquired))
          .whenComplete(() => markCompleted(acquired));
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

      return completer.future
          .whenComplete(() => markCompleted(waiter.acquiredItems));
    }
  }
}

final class _MultiSemaphoreWaiter<T> {
  final List<T> acquiredItems = [];
  final void Function() onAcquireComplete;
  int remaining;

  _MultiSemaphoreWaiter(this.remaining, this.onAcquireComplete);
}
