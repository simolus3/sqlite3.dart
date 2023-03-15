import 'dart:typed_data';

import '../functions.dart';

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

typedef RawXFunc = void Function(RawSqliteContext, List<RawSqliteValue>);
typedef RawXStep = void Function(RawSqliteContext, List<RawSqliteValue>);
typedef RawXFinal = void Function(RawSqliteContext);
typedef RawUpdateHook = void Function(int kind, String tableName, int rowId);
typedef RawCollation = int Function(String? a, String? b);

abstract class RawSqliteDatabase {
  int sqlite3_changes();
  int sqlite3_last_insert_rowid();

  int sqlite3_exec(String sql);

  int sqlite3_extended_errcode();
  void sqlite3_extended_result_codes(int onoff);
  int sqlite3_close_v2();
  void deallocateAdditionalMemory();
  String sqlite3_errmsg();

  void sqlite3_update_hook(RawUpdateHook? hook);

  RawStatementCompiler newCompiler(List<int> utf8EncodedSql);

  int sqlite3_create_collation_v2({
    required Uint8List collationName,
    required int eTextRep,
    required RawCollation collation,
  });

  int sqlite3_create_function_v2({
    required Uint8List functionName,
    required int nArg,
    required int eTextRep,
    RawXFunc? xFunc,
    RawXStep? xStep,
    RawXFinal? xFinal,
  });

  int sqlite3_create_window_function({
    required Uint8List functionName,
    required int nArg,
    required int eTextRep,
    required RawXStep xStep,
    required RawXFinal xFinal,
    required RawXFinal xValue,
    required RawXStep xInverse,
  });
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

abstract class RawSqliteContext {
  abstract AggregateContext<Object?>? dartAggregateContext;

  void sqlite3_result_null();
  void sqlite3_result_int64(int value);
  void sqlite3_result_int64BigInt(BigInt value);
  void sqlite3_result_double(double value);
  void sqlite3_result_text(String text);
  void sqlite3_result_blob64(List<int> blob);
  void sqlite3_result_error(String message);
}

abstract class RawSqliteValue {
  int sqlite3_value_type();
  int sqlite3_value_int64();
  double sqlite3_value_double();
  String sqlite3_value_text();
  Uint8List sqlite3_value_blob();
}
