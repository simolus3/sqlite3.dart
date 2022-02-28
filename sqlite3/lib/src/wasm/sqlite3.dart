import 'package:wasm_interop/wasm_interop.dart';

import '../common/constants.dart';
import '../common/database.dart';
import '../common/impl/database.dart';
import '../common/sqlite3.dart';
import 'bindings.dart';
import 'database.dart';
import 'environment.dart';
import 'exception.dart';

class WasmSqlite3 implements CommmonSqlite3 {
  final WasmBindings _bindings;

  factory WasmSqlite3(Module wasmModule) {
    return WasmSqlite3._(
        WasmBindings.instantiate(wasmModule, SqliteEnvironment()));
  }

  static Future<WasmSqlite3> createAsync(Module wasmModule) {
    return WasmBindings.instantiateAsync(wasmModule, SqliteEnvironment())
        .then(WasmSqlite3._);
  }

  WasmSqlite3._(this._bindings);

  @override
  CommonDatabase open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  }) {
    final flags = flagsForOpen(mode: mode, uri: uri, mutex: mutex);

    final namePtr = _bindings.allocateZeroTerminated(filename);
    final outDb = _bindings.malloc(WasmBindings.pointerSize);
    final vfsPtr = vfs == null ? 0 : _bindings.allocateZeroTerminated(vfs);

    final result = _bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);
    final dbPtr = _bindings.int32ValueOfPointer(outDb);

    // Free pointers we allocateed
    _bindings
      ..free(namePtr)
      ..free(vfsPtr);
    if (vfs != null) _bindings.free(vfsPtr);

    if (result != SqlError.SQLITE_OK) {
      _bindings.sqlite3_close_v2(dbPtr);
      throw createExceptionRaw(_bindings, dbPtr, result);
    }

    // Enable extended error codes by default.
    _bindings.sqlite3_extended_result_codes(dbPtr, 1);

    return WasmDatabase(_bindings, dbPtr);
  }

  @override
  CommonDatabase openInMemory() => open(':memory:');

  @override
  Version get version {
    final libVersion =
        _bindings.memory.readString(_bindings.sqlite3_libversion());
    final sourceId = _bindings.memory.readString(_bindings.sqlite3_sourceid());
    final versionNumber = _bindings.sqlite3_libversion_number();

    return Version(libVersion, sourceId, versionNumber);
  }

  @override
  String? get tempDirectory {
    final charPtr = _bindings.sqlite3_temp_directory;
    if (charPtr == 0) {
      return null;
    } else {
      return _bindings.memory.readString(charPtr);
    }
  }

  @override
  set tempDirectory(String? value) {
    if (value == null) {
      _bindings.sqlite3_temp_directory = 0;
    } else {
      _bindings.sqlite3_temp_directory =
          _bindings.allocateZeroTerminated(value);
    }
  }
}
