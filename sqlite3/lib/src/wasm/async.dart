import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';

final class _AsyncCallbackEntry extends LinkedListEntry<_AsyncCallbackEntry> {
  final void Function() callback;

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
  final callbackList = LinkedList<_AsyncCallbackEntry>();

  void runTasks() {
    while (callbackList.isNotEmpty) {
      final item = callbackList.first..unlink();
      item.callback();
    }
  }

  final runTasksJs = runTasks.toJS;

  void addTask(void Function() callback) {
    final emptyBefore = callbackList.isEmpty;
    callbackList.add(_AsyncCallbackEntry(callback));

    if (emptyBefore) {
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
