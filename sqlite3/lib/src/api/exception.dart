/// Thrown by sqlite methods.
///
/// This is the only exception thrown by `package:sqlite3`. Additionally, errors
/// might be thrown on api misuse.
class SqliteException implements Exception {
  /// An error message indicating what went wrong.
  final String message;

  /// An optional explanation providing more detail on what went wrong.
  final String? explanation;

  /// SQLite extended result code.
  ///
  /// As defined in https://sqlite.org/rescode.html, it represents an error
  /// code, providing some idea of the cause of the failure.
  final int extendedResultCode;

  /// SQLite primary result code.
  ///
  /// As defined in https://sqlite.org/rescode.html, it represents an error
  /// code, providing some idea of the cause of the failure.
  int get resultCode => extendedResultCode & 0xFF;

  /// The SQL statement triggering this exception.
  String? sqlStatement;

  SqliteException(this.extendedResultCode, this.message,
      [this.explanation, this.sqlStatement]);

  @override
  String toString() {
    if (explanation == null) {
      return '''
SqliteException($extendedResultCode): $message
    SQL: $sqlStatement
      ''';
    } else {
      return '''
SqliteException($extendedResultCode): $message, $explanation
    SQL: $sqlStatement
''';
    }
  }
}
