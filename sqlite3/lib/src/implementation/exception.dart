import '../exception.dart';
import 'bindings.dart';
import 'database.dart';

SqliteException createExceptionOutsideOfDatabase(
    RawSqliteBindings bindings, int resultCode,
    {String? operation}) {
  final errStr = bindings.sqlite3_errstr(resultCode);

  return SqliteException(resultCode, errStr, null, null, null, operation, null);
}

SqliteException createExceptionRaw(
  RawSqliteBindings bindings,
  RawSqliteDatabase db,
  int returnCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
}) {
  // Getting hold of more explanatory error code as SQLITE_IOERR error group has
  // an extensive list of extended error codes
  final extendedCode = db.sqlite3_extended_errcode();
  final offset = switch (db.sqlite3_error_offset()) {
    < 0 => null,
    final offset => offset,
  };

  return createExceptionFromExtendedCode(
    bindings,
    db,
    returnCode,
    extendedCode,
    operation: operation,
    previousStatement: previousStatement,
    statementArgs: statementArgs,
    offset: offset,
  );
}

SqliteException createExceptionFromExtendedCode(
  RawSqliteBindings bindings,
  RawSqliteDatabase db,
  int returnCode,
  int extendedErrorCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
  int? offset,
}) {
  // We don't need to free the pointer returned by sqlite3_errmsg: "Memory to
  // hold the error message string is managed internally. The application does
  // not need to worry about freeing the result."
  // https://www.sqlite.org/c3ref/errcode.html
  final dbMessage = db.sqlite3_errmsg();
  final errStr = bindings.sqlite3_errstr(extendedErrorCode);
  final explanation = '$errStr (code $extendedErrorCode)';

  return SqliteException(
    returnCode,
    dbMessage,
    explanation,
    previousStatement,
    statementArgs,
    operation,
    offset,
  );
}

SqliteException createException(
  DatabaseImplementation db,
  int returnCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
}) {
  return createExceptionRaw(
    db.bindings,
    db.database,
    returnCode,
    operation: operation,
    previousStatement: previousStatement,
    statementArgs: statementArgs,
  );
}

Never throwException(
  DatabaseImplementation db,
  int returnCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
  int? offset,
}) {
  throw createException(
    db,
    returnCode,
    operation: operation,
    previousStatement: previousStatement,
    statementArgs: statementArgs,
  );
}
