import 'package:wasm_interop/wasm_interop.dart';

import '../common/database.dart';
import '../common/sqlite3.dart';
import 'bindings.dart';

class WasmSqlite3 implements CommmonSqlite3 {
  final WasmBindings _bindings;

  factory WasmSqlite3(Module wasmModule) {
    return WasmSqlite3._(WasmBindings.instantiate(wasmModule));
  }

  static Future<WasmSqlite3> createAsync(Module wasmModule) {
    return WasmBindings.instantiateAsync(wasmModule).then(WasmSqlite3._);
  }

  WasmSqlite3._(this._bindings);

  @override
  CommonDatabase open(String filename,
      {String? vfs,
      OpenMode mode = OpenMode.readWriteCreate,
      bool uri = false,
      bool? mutex}) {
    // TODO: implement open
    throw UnimplementedError();
  }

  @override
  CommonDatabase openInMemory() => open(':memory:');

  @override
  Version get version {
    final libVersion = _bindings.readString(_bindings.sqlite3_libversion());
    final sourceId = _bindings.readString(_bindings.sqlite3_sourceid());
    final versionNumber = _bindings.sqlite3_libversion_number();

    return Version(libVersion, sourceId, versionNumber);
  }

  @override
  String? get tempDirectory {
    final charPtr = _bindings.sqlite3_temp_directory;
    if (charPtr == 0) {
      return null;
    } else {
      return _bindings.readString(charPtr);
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
