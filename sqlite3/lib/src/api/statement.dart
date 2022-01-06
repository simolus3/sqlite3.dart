import 'dart:ffi';

import 'exception.dart';
import 'result_set.dart';

/// A prepared statement.
abstract class PreparedStatement {
  /// The SQL statement backing this prepared statement.
  String get sql;

  /// Returns the amount of parameters in this prepared statement.
  int get parameterCount;

  /// The underlying `sqlite3_stmt` pointer.
  ///
  /// Obtains the raw [statement](https://www.sqlite.org/c3ref/stmt.html) from
  /// the sqlite3 C-api that this [PreparedStatement] wraps.
  Pointer<void> get handle;

  /// Executes this statement, ignoring result rows if there are any.
  ///
  /// If the [parameters] list does not match the amount of parameters in the
  /// original SQL statement ([parameterCount]), an [ArgumentError] will be
  /// thrown.
  /// If sqlite3 reports an error while running this statement, a
  /// [SqliteException] will be thrown.
  void execute([List<Object?> parameters = const <Object>[]]);

  /// Executes this statement, ignoring result rows if there are any.
  ///
  /// Unlike [execute], which binds parameters by their index, [executeMap]
  /// binds parameters by their name.
  /// For instance, a SQL query `SELECT :foo, @bar;` has two named parameters
  /// (`:foo` and `@bar`) that can occur as keys in [parameters].
  ///
  /// If the keys in [parameters] do not match the names of parameters in this
  /// query, an [ArgumentError] will be thrown.
  /// If sqlite3 reports an error while running this statement, a
  /// [SqliteException] will be thrown.
  void executeMap(Map<String, Object?> parameters);

  /// Selects all rows into a [ResultSet].
  ///
  /// If the [parameters] list does not match the amount of parameters in the
  /// original SQL statement ([parameterCount]), an [ArgumentError] will be
  /// thrown.
  /// If sqlite3 reports an error while running this statement, a
  /// [SqliteException] will be thrown.
  ResultSet select([List<Object?> parameters = const <Object>[]]);

  /// Selects all rows into a [ResultSet].
  ///
  /// Similar to [executeMap], parameters are bound by their name instead of
  /// their index.
  ResultSet selectMap(Map<String, Object?> parameters);

  /// Starts selecting rows by running this prepared statement with the given
  /// [parameters].
  ///
  /// If the [parameters] list does not match the amount of parameters in the
  /// original SQL statement ([parameterCount]), an [ArgumentError] will be
  /// thrown.
  ///
  /// If sqlite3 reports an error while running this statement, it will be
  /// thrown by a call to [Iterator.moveNext].
  ///
  /// The iterator returned here will become invalid with the next call to
  /// [execute], [select] or [selectCursor].
  IteratingCursor selectCursor([List<Object?> parameters = const <Object>[]]);

  /// Disposes this statement and releases associated memory.
  void dispose();
}
