import 'dart:typed_data';

import 'finalizer.dart';

abstract class RawSqliteBindings {
  String sqlite3_libversion();
  String sqlite3_sourceid();
  int sqlite3_libversion_number();

  String? sqlite3_temp_directory;

  SqliteResult<RawSqliteDatabase> sqlite3_open_v2(
      String name, int flags, String? zVfs);

  String sqlite3_errstr(int extendedErrorCode);
}

class SqliteResult<T> {
  final int resultCode;
  final T result;

  SqliteResult(this.resultCode, this.result);
}

abstract class RawSqliteDatabase {
  int sqlite3_changes();
  int sqlite3_last_insert_rowid();

  int sqlite3_exec(String sql);

  int sqlite3_extended_errcode();
  void sqlite3_extended_result_codes(int onoff);
  int sqlite3_close_v2();
  void deallocateAdditionalMemory();
  String sqlite3_errmsg();

  RawStatementCompiler newCompiler(List<int> utf8EncodedSql);
}

/// A stateful wrapper around multiple `sqlite3_prepare` invocations.
abstract class RawStatementCompiler {
  int get endOffset;

  SqliteResult<RawSqliteStatement?> sqlite3_prepare(
      int byteOffset, int length, int prepFlag);

  void close();
}

abstract class RawSqliteStatement {
  void sqlite3_reset();
  int sqlite3_step();
  void sqlite3_finalize();
  void deallocateArguments();

  int sqlite3_bind_parameter_index(String name);

  void sqlite3_bind_null(int index);
  void sqlite3_bind_int64(int index, int value);
  void sqlite3_bind_int64BigInt(int index, BigInt value);
  void sqlite3_bind_double(int index, double value);
  void sqlite3_bind_text(int index, String value);
  void sqlite3_bind_blob64(int index, List<int> value);

  int sqlite3_column_count();
  String sqlite3_column_name(int index);
  bool get supportsReadingTableNameForColumn;
  String? sqlite3_column_table_name(int index);

  int sqlite3_column_type(int index);
  int sqlite3_column_int64(int index);
  BigInt sqlite3_column_int64BigInt(int index);
  double sqlite3_column_double(int index);
  String sqlite3_column_text(int index);
  Uint8List sqlite3_column_bytes(int index);

  int sqlite3_bind_parameter_count();
}
