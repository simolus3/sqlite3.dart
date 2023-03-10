import '../implementation/bindings.dart';
import 'wasm_interop.dart' as wasm;

class WasmBindings implements RawSqliteBindings {
  final wasm.WasmBindings bindings;

  WasmBindings(this.bindings);

  @override
  String? get sqlite3_temp_directory {
    final charPtr = bindings.sqlite3_temp_directory;
    if (charPtr == 0) {
      return null;
    } else {
      return bindings.memory.readString(charPtr);
    }
  }

  @override
  set sqlite3_temp_directory(String? value) {
    if (value == null) {
      bindings.sqlite3_temp_directory = 0;
    } else {
      bindings.sqlite3_temp_directory = bindings.allocateZeroTerminated(value);
    }
  }

  @override
  String sqlite3_errstr(int extendedErrorCode) {
    return bindings.memory
        .readString(bindings.sqlite3_errstr(extendedErrorCode));
  }

  @override
  String sqlite3_libversion() {
    return bindings.memory.readString(bindings.sqlite3_libversion());
  }

  @override
  int sqlite3_libversion_number() {
    return bindings.sqlite3_libversion_number();
  }

  @override
  SqliteOpenResult sqlite3_open_v2(String name, int flags, String? zVfs) {
    final namePtr = bindings.allocateZeroTerminated(name);
    final outDb = bindings.malloc(wasm.WasmBindings.pointerSize);
    final vfsPtr = zVfs == null ? 0 : bindings.allocateZeroTerminated(zVfs);

    final result = bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);
    final dbPtr = bindings.int32ValueOfPointer(outDb);

    // Free pointers we allocateed
    bindings
      ..free(namePtr)
      ..free(vfsPtr);
    if (zVfs != null) bindings.free(vfsPtr);

    return SqliteOpenResult(result, WasmDatabase(bindings, dbPtr));
  }

  @override
  String sqlite3_sourceid() {
    return bindings.memory.readString(bindings.sqlite3_sourceid());
  }
}

class WasmDatabase implements RawSqliteDatabase {
  final wasm.WasmBindings bindings;
  final wasm.Pointer db;

  WasmDatabase(this.bindings, this.db);

  @override
  int sqlite3_close_v2() {
    return bindings.sqlite3_close_v2(db);
  }

  @override
  String sqlite3_errmsg() {
    return bindings.memory.readString(bindings.sqlite3_errmsg(db));
  }

  @override
  int sqlite3_extended_errcode() {
    return bindings.sqlite3_extended_errcode(db);
  }

  @override
  void sqlite3_extended_result_codes(int onoff) {
    bindings.sqlite3_extended_result_codes(db, onoff);
  }
}
