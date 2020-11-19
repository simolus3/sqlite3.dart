import 'dart:ffi';

import 'result_set.dart';

/// A prepared statement.
abstract class PreparedStatement {
  /// Returns the amount of parameters in this prepared statement.
  int get parameterCount;

  /// The underlying `sqlite3_stmt` pointer.
  ///
  /// Obtains the raw [statement](https://www.sqlite.org/c3ref/stmt.html) from
  /// the sqlite3 C-api that this [PreparedStatement] wraps.
  Pointer<void> get handle;

  /// If this statement contains parameters and [parameters] is too short, an
  /// exception will be thrown.
  void execute([List<Object?> parameters = const <Object>[]]);

  /// If this statement contains parameters and [parameters] is too short, an
  /// exception will be thrown.
  ResultSet select([List<Object?> parameters = const <Object>[]]);

  /// Disposes this statement and releases associated memory.
  void dispose();
}
