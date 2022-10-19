import 'dart:typed_data';

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
  ///
  /// This may be null when no prior statement is known.
  final String? causingStatement;

  /// If this exception has a [causingStatement], this list contains the
  /// parameters used to run that statement.
  final List<Object?>? parametersToStatement;

  SqliteException(this.extendedResultCode, this.message,
      [this.explanation, this.causingStatement, this.parametersToStatement]);

  @override
  String toString() {
    final buffer = StringBuffer('SqliteException(')
      ..write(extendedResultCode)
      ..write('): ')
      ..write(message);

    if (explanation != null) {
      buffer
        ..write(', ')
        ..write(explanation);
    }

    if (causingStatement != null) {
      buffer
        ..writeln()
        ..write('  Causing statement: ')
        ..write(causingStatement);

      if (parametersToStatement != null) {
        final params = parametersToStatement!.map((e) {
          if (e is Uint8List) {
            return 'blob (${e.length} bytes)';
          } else {
            return e.toString();
          }
        }).join(', ');
        buffer.write(', parameters: $params');
      }
    }

    return buffer.toString();
  }
}
