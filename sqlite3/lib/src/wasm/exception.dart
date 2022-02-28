import '../common/exception.dart';

import 'bindings.dart';

SqliteException createExceptionRaw(
    WasmBindings bindings, Pointer db, int returnCode,
    [String? previousStatement]) {
  // We don't need to free the pointer returned by sqlite3_errmsg: "Memory to
  // hold the error message string is managed internally. The application does
  // not need to worry about freeing the result."
  // https://www.sqlite.org/c3ref/errcode.html
  final dbMessage = bindings.memory.readString(bindings.sqlite3_errmsg(db));

  String explanation;

  // Getting hold of more explanatory error code as SQLITE_IOERR error group
  // has an extensive list of extended error codes
  final extendedCode = bindings.sqlite3_extended_errcode(db);
  final errStr =
      bindings.memory.readString(bindings.sqlite3_errstr(extendedCode));

  explanation = '$errStr (code $extendedCode)';

  return SqliteException(returnCode, dbMessage, explanation, previousStatement);
}
