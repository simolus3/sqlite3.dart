part of 'implementation.dart';

int _id = 0;
final Map<int, List<MultiStreamController<SqliteUpdate>>> _listeners = {};

void _updateCallback(Pointer<Void> data, int kind, Pointer<sqlite3_char> db,
    Pointer<sqlite3_char> table, int rowid) {
  SqliteUpdateKind updateKind;

  switch (kind) {
    case SQLITE_INSERT:
      updateKind = SqliteUpdateKind.insert;
      break;
    case SQLITE_UPDATE:
      updateKind = SqliteUpdateKind.update;
      break;
    case SQLITE_DELETE:
      updateKind = SqliteUpdateKind.delete;
      break;
    default:
      return;
  }

  final tableName = table.readString();
  final update = SqliteUpdate(updateKind, tableName, rowid);
  final listeners = _listeners[data.address];

  if (listeners != null) {
    for (final listener in listeners) {
      listener.add(update);
    }
  }
}

final Pointer<NativeType> _updateCallbackPtr = Pointer.fromFunction<
    Void Function(Pointer<Void>, Int32, Pointer<sqlite3_char>,
        Pointer<sqlite3_char>, Int64)>(_updateCallback);

class _DatabaseUpdates {
  final DatabaseImpl impl;
  final int id = _id++;
  final List<MultiStreamController<SqliteUpdate>> listeners = [];
  bool closed = false;

  _DatabaseUpdates(this.impl);

  Stream<SqliteUpdate> get updates {
    return Stream.multi((listener) {
      if (closed) {
        listener.closeSync();
        return;
      }

      addListener(listener);

      listener
        ..onPause = (() => removeListener(listener))
        ..onResume = (() => addListener(listener))
        ..onCancel = (() => removeListener(listener));
    }, isBroadcast: true);
  }

  void registerNativeCallback() {
    impl._bindings.sqlite3_update_hook(
      impl._handle,
      _updateCallbackPtr.cast(),
      Pointer.fromAddress(id),
    );
  }

  void unregisterNativeCallback() {
    impl._bindings.sqlite3_update_hook(
      impl._handle,
      nullPtr(),
      Pointer.fromAddress(id),
    );
  }

  void addListener(MultiStreamController<SqliteUpdate> listener) {
    final isFirstListener = listeners.isEmpty;
    listeners.add(listener);

    if (isFirstListener) {
      _listeners[id] = listeners;
      registerNativeCallback();
    }
  }

  void removeListener(MultiStreamController<SqliteUpdate> listener) {
    listeners.remove(listener);

    if (listeners.isEmpty && !closed) {
      unregisterNativeCallback();
    }
  }

  void close() {
    closed = true;
    for (final listener in listeners) {
      listener.close();
    }

    unregisterNativeCallback();
  }
}
