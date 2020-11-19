part of 'implementation.dart';

SqliteException createExceptionRaw(
    Bindings bindings, Pointer<sqlite3> db, int returnCode) {
  // We don't need to free the pointer returned by sqlite3_errmsg: "Memory to
  // hold the error message string is managed internally. The application does
  // not need to worry about freeing the result."
  // https://www.sqlite.org/c3ref/errcode.html
  final dbMessage = bindings.sqlite3_errmsg(db).readString();

  String explanation;

  // Getting hold of more explanatory error code as SQLITE_IOERR error group
  // has an extensive list of extended error codes
  final extendedCode = bindings.sqlite3_extended_errcode(db);
  final errStr = bindings.sqlite3_errstr(extendedCode).readString();

  explanation = '$errStr (code $extendedCode)';

  return SqliteException(returnCode, dbMessage, explanation);
}

SqliteException createException(DatabaseImpl db, int returnCode) {
  final bindings = db._bindings;
  final handle = db._handle;

  return createExceptionRaw(bindings, handle, returnCode);
}

void throwException(DatabaseImpl db, int returnCode) {
  throw createException(db, returnCode);
}
