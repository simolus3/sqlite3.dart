import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import '../implementation/bindings.dart';
import 'memory.dart';
import 'sqlite3.g.dart';

class BindingsWithLibrary {
  // sqlite3_prepare_v3 was added in 3.20.0
  static const int _firstVersionForV3 = 3020000;

  final Bindings bindings;
  final DynamicLibrary library;

  final bool supportsPrepareV3;
  final bool supportsColumnTableName;

  factory BindingsWithLibrary(DynamicLibrary library) {
    final bindings = Bindings(library);
    var hasColumnMetadata = false;

    if (library.providesSymbol('sqlite3_compileoption_get')) {
      var i = 0;
      String? lastOption;
      do {
        final ptr = bindings.sqlite3_compileoption_get(i);

        if (!ptr.isNullPointer) {
          lastOption = ptr.readString();

          if (lastOption == 'ENABLE_COLUMN_METADATA') {
            hasColumnMetadata = true;
            break;
          }
        } else {
          lastOption = null;
        }

        i++;
      } while (lastOption != null);
    }

    return BindingsWithLibrary._(
      bindings,
      library,
      bindings.sqlite3_libversion_number() >= _firstVersionForV3,
      hasColumnMetadata,
    );
  }

  BindingsWithLibrary._(this.bindings, this.library, this.supportsPrepareV3,
      this.supportsColumnTableName);
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
  SqliteResult<RawSqliteDatabase> sqlite3_open_v2(
      String name, int flags, String? zVfs) {
    final namePtr = Utf8Utils.allocateZeroTerminated(name);
    final outDb = allocate<Pointer<sqlite3>>();
    final vfsPtr = zVfs == null
        ? nullPtr<sqlite3_char>()
        : Utf8Utils.allocateZeroTerminated(zVfs);

    final resultCode =
        bindings.bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);
    final result = SqliteResult(resultCode, FfiDatabase(bindings, outDb.value));

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

  @override
  void deallocateAdditionalMemory() {}

  @override
  RawStatementCompiler newCompiler(List<int> utf8EncodedSql) {
    return FfiStatementCompiler(this, allocateBytes(utf8EncodedSql));
  }
}

class FfiStatementCompiler implements RawStatementCompiler {
  final FfiDatabase database;
  final Pointer<Uint8> sql;
  final Pointer<Pointer<sqlite3_stmt>> stmtOut = allocate();
  final Pointer<Pointer<sqlite3_char>> pzTail = allocate();

  FfiStatementCompiler(this.database, this.sql);

  @override
  void close() {
    sql.free();
    stmtOut.free();
    pzTail.free();
  }

  @override
  int get endOffset => pzTail.value.address - sql.address;

  @override
  SqliteResult<RawSqliteStatement?> sqlite3_prepare(
      int byteOffset, int length, int prepFlag) {
    final int result;

    if (database.bindings.supportsPrepareV3) {
      result = database.bindings.bindings.sqlite3_prepare_v3(
        database.db,
        sql.elementAt(byteOffset).cast(),
        length,
        prepFlag,
        stmtOut,
        pzTail,
      );
    } else {
      assert(
        prepFlag == 0,
        'Used custom preparation flags, but the loaded sqlite library does '
        'not support prepare_v3',
      );

      result = database.bindings.bindings.sqlite3_prepare_v2(
        database.db,
        sql.elementAt(byteOffset).cast(),
        length,
        stmtOut,
        pzTail,
      );
    }

    final stmt = stmtOut.value;
    final libraryStatement =
        stmt.isNullPointer ? null : FfiStatement(database, stmt);

    return SqliteResult(result, libraryStatement);
  }
}

class FfiStatement implements RawSqliteStatement {
  final FfiDatabase database;
  final Bindings bindings;
  final Pointer<sqlite3_stmt> stmt;

  final List<Pointer> _allocatedArguments = [];

  FfiStatement(this.database, this.stmt)
      : bindings = database.bindings.bindings;

  @override
  void deallocateArguments() {
    for (final arg in _allocatedArguments) {
      arg.free();
    }
    _allocatedArguments.clear();
  }

  @override
  void sqlite3_bind_blob64(int index, List<int> value) {
    final ptr = allocateBytes(value);
    _allocatedArguments.add(ptr);

    bindings.sqlite3_bind_blob64(
        stmt, index, ptr.cast(), value.length, nullPtr());
  }

  @override
  void sqlite3_bind_double(int index, double value) {
    bindings.sqlite3_bind_double(stmt, index, value);
  }

  @override
  void sqlite3_bind_int64(int index, int value) {
    bindings.sqlite3_bind_int64(stmt, index, value);
  }

  @override
  void sqlite3_bind_int64BigInt(int index, BigInt value) {
    bindings.sqlite3_bind_int64(stmt, index, value.toInt());
  }

  @override
  void sqlite3_bind_null(int index) {
    bindings.sqlite3_bind_null(stmt, index);
  }

  @override
  int sqlite3_bind_parameter_count() {
    return bindings.sqlite3_bind_parameter_count(stmt);
  }

  @override
  int sqlite3_bind_parameter_index(String name) {
    final ptr = Utf8Utils.allocateZeroTerminated(name);
    try {
      return bindings.sqlite3_bind_parameter_index(stmt, ptr);
    } finally {
      ptr.free();
    }
  }

  @override
  void sqlite3_bind_text(int index, String value) {
    final bytes = utf8.encode(value);
    final ptr = allocateBytes(bytes);
    _allocatedArguments.add(ptr);

    bindings.sqlite3_bind_text(
        stmt, index, ptr.cast(), bytes.length, nullPtr());
  }

  @override
  Uint8List sqlite3_column_bytes(int index) {
    final length = bindings.sqlite3_column_bytes(stmt, index);
    if (length == 0) {
      // sqlite3_column_blob returns a null pointer for non-null blobs with
      // a length of 0. Note that we can distinguish this from a proper null
      // by checking the type (which isn't SQLITE_NULL)
      return Uint8List(0);
    }
    return bindings.sqlite3_column_blob(stmt, index).copyRange(length);
  }

  @override
  int sqlite3_column_count() {
    return bindings.sqlite3_column_count(stmt);
  }

  @override
  double sqlite3_column_double(int index) {
    return bindings.sqlite3_column_double(stmt, index);
  }

  @override
  int sqlite3_column_int64(int index) {
    return bindings.sqlite3_column_int64(stmt, index);
  }

  @override
  BigInt sqlite3_column_int64BigInt(int index) {
    return BigInt.from(bindings.sqlite3_column_int64(stmt, index));
  }

  @override
  String sqlite3_column_name(int index) {
    return bindings.sqlite3_column_name(stmt, index).readString();
  }

  @override
  String? sqlite3_column_table_name(int index) {
    return bindings.sqlite3_column_table_name(stmt, index).readNullableString();
  }

  @override
  String sqlite3_column_text(int index) {
    final length = bindings.sqlite3_column_bytes(stmt, index);
    return bindings.sqlite3_column_text(stmt, index).readString(length);
  }

  @override
  int sqlite3_column_type(int index) {
    return bindings.sqlite3_column_type(stmt, index);
  }

  @override
  void sqlite3_finalize() {
    bindings.sqlite3_finalize(stmt);
  }

  @override
  void sqlite3_reset() {
    bindings.sqlite3_reset(stmt);
  }

  @override
  int sqlite3_step() {
    return bindings.sqlite3_step(stmt);
  }

  @override
  bool get supportsReadingTableNameForColumn =>
      database.bindings.supportsColumnTableName;
}
