import 'dart:async';
import 'dart:js_interop';

final class _AsyncCallbackEntry {
  final void Function() callback;
  _AsyncCallbackEntry? next;

  _AsyncCallbackEntry(this.callback);
}

/// Runs a block in a zone guaranteed to use `Promise.resolve().then()` for
/// microtasks.
///
/// IndexedDB transactions will commit automatically if they're not immediately
/// used after a completed IndexedDB event. We can use the native microtask loop
/// of the JavaScript engine for async work after events, but unfortunately
/// `dart2js` uses a [different implementation](https://github.com/dart-lang/sdk/blob/main/sdk/lib/_internal/js_runtime/lib/async_patch.dart)
/// based on `setTimeout` in workers.
///
/// Using `setTimeout` breaks IndexedDB, which is why we need to avoid it in
/// transactions. This function patches [scheduleMicrotask] to be based on
/// native microtasks instead.
T runWithNativeMicrotasks<T>(T Function() callback) {
  _AsyncCallbackEntry? firstPendingTask;

  void runTasks() {
    while (true) {
      if (firstPendingTask case final task?) {
        firstPendingTask = task.next;
        task.callback();
      } else {
        break;
      }
    }
  }

  final runTasksJs = runTasks.toJS;

  void addTask(void Function() callback) {
    if (firstPendingTask case final existing?) {
      existing.next = _AsyncCallbackEntry(callback);
    } else {
      firstPendingTask = _AsyncCallbackEntry(callback);
      _promiseResolve().then(runTasksJs);
    }
  }

  return runZoned(
    callback,
    zoneSpecification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) {
        addTask(zone.bindCallbackGuarded(f));
      },
    ),
  );
}

@JS('Promise.resolve')
external _Promise _promiseResolve();

extension type _Promise(JSPromise _) implements JSPromise {
  @JS()
  external void then(JSFunction callback);
}
