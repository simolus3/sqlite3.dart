import 'dart:ffi';

import '../implementation/bindings.dart';
import 'memory.dart';
import 'sqlite3.g.dart';

class BindingsWithLibrary {
  final Bindings bindings;
  final DynamicLibrary library;

  BindingsWithLibrary(this.library) : bindings = Bindings(library);
}

class FfiBindings implements RawSqliteBindings {
  final BindingsWithLibrary bindings;

  FfiBindings(this.bindings);

  @override
  String? get sqlite3_temp_directory {
    return bindings.bindings.sqlite3_temp_directory.readNullableString();
  }

  @override
  set sqlite3_temp_directory(String? value) {
    if (value == null) {
      bindings.bindings.sqlite3_temp_directory = nullPtr();
    } else {
      bindings.bindings.sqlite3_temp_directory =
          Utf8Utils.allocateZeroTerminated(value);
    }
  }

  @override
  String sqlite3_errstr(int extendedErrorCode) {
    return bindings.bindings.sqlite3_errstr(extendedErrorCode).readString();
  }

  @override
  String sqlite3_libversion() {
    return bindings.bindings.sqlite3_libversion().readString();
  }

  @override
  int sqlite3_libversion_number() {
    return bindings.bindings.sqlite3_libversion_number();
  }

  @override
  SqliteOpenResult sqlite3_open_v2(String name, int flags, String? zVfs) {
    final namePtr = Utf8Utils.allocateZeroTerminated(name);
    final outDb = allocate<Pointer<sqlite3>>();
    final vfsPtr = zVfs == null
        ? nullPtr<sqlite3_char>()
        : Utf8Utils.allocateZeroTerminated(zVfs);

    final resultCode =
        bindings.bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);
    final result =
        SqliteOpenResult(resultCode, FfiDatabase(bindings, outDb.value));

    namePtr.free();
    outDb.free();
    if (zVfs != null) vfsPtr.free();

    return result;
  }

  @override
  String sqlite3_sourceid() {
    return bindings.bindings.sqlite3_sourceid().readString();
  }
}

class FfiDatabase implements RawSqliteDatabase {
  final BindingsWithLibrary bindings;
  final Pointer<sqlite3> db;

  FfiDatabase(this.bindings, this.db);

  @override
  int sqlite3_close_v2() {
    return bindings.bindings.sqlite3_close_v2(db);
  }

  @override
  String sqlite3_errmsg() {
    return bindings.bindings.sqlite3_errmsg(db).readString();
  }

  @override
  int sqlite3_extended_errcode() {
    return bindings.bindings.sqlite3_extended_errcode(db);
  }

  @override
  void sqlite3_extended_result_codes(int onoff) {
    bindings.bindings.sqlite3_extended_result_codes(db, onoff);
  }

  @override
  int sqlite3_changes() => bindings.bindings.sqlite3_changes(db);

  @override
  int sqlite3_exec(String sql) {
    final sqlPtr = Utf8Utils.allocateZeroTerminated(sql);

    final result = bindings.bindings
        .sqlite3_exec(db, sqlPtr, nullPtr(), nullPtr(), nullPtr());
    sqlPtr.free();
    return result;
  }

  @override
  int sqlite3_last_insert_rowid() {
    return bindings.bindings.sqlite3_last_insert_rowid(db);
  }
}
