part of 'implementation.dart';

SqliteException createExceptionRaw(
  Bindings bindings,
  Pointer<sqlite3> db,
  int returnCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
}) {
  // Getting hold of more explanatory error code as SQLITE_IOERR error group has
  // an extensive list of extended error codes
  final extendedCode = bindings.sqlite3_extended_errcode(db);
  return createExceptionFromExtendedCode(
    bindings,
    db,
    returnCode,
    extendedCode,
    operation: operation,
    previousStatement: previousStatement,
    statementArgs: statementArgs,
  );
}

SqliteException createExceptionFromExtendedCode(
  Bindings bindings,
  Pointer<sqlite3> db,
  int returnCode,
  int extendedErrorCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
}) {
  // We don't need to free the pointer returned by sqlite3_errmsg: "Memory to
  // hold the error message string is managed internally. The application does
  // not need to worry about freeing the result."
  // https://www.sqlite.org/c3ref/errcode.html
  final dbMessage = bindings.sqlite3_errmsg(db).readString();

  final errStr = bindings.sqlite3_errstr(extendedErrorCode).readString();
  final explanation = '$errStr (code $extendedErrorCode)';

  return SqliteException(
    returnCode,
    dbMessage,
    explanation,
    previousStatement,
    statementArgs,
    operation,
  );
}

SqliteException createException(
  DatabaseImpl db,
  int returnCode, {
  String? operation,
  String? previousStatement,
  List<Object?>? statementArgs,
}) {
  final bindings = db._bindings;
  final handle = db._finalizable._handle;

  return createExceptionRaw(
    bindings,
    handle,
    returnCode,
    operation: operation,
    previousStatement: previousStatement,
    statementArgs: statementArgs,
  );
}

Never throwException(DatabaseImpl db, int returnCode,
    {String? operation,
    String? previousStatement,
    List<Object?>? statementArgs}) {
  throw createException(
    db,
    returnCode,
    operation: operation,
    previousStatement: previousStatement,
    statementArgs: statementArgs,
  );
}
