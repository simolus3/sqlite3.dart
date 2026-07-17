/// @docImport 'wasm/sqlite3.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'exception.dart';
import 'implementation/bindings.dart';
import 'implementation/statement.dart';
import 'result_set.dart';

/// A prepared statement.
///
/// {@category common}
abstract class CommonPreparedStatement {
  /// Unsafe, raw access to the underlying SQLite statement.
  ///
  /// For more details, see [RawPreparedStatement].
  RawPreparedStatement get raw;

  /// The SQL statement backing this prepared statement.
  String get sql;

  /// Returns the amount of parameters in this prepared statement.
  int get parameterCount;

  /// Returns whether this statement makes no direct changes to the contents of
  /// the database file.
  ///
  /// See also: https://www.sqlite.org/c3ref/stmt_readonly.html
  bool get isReadOnly;

  /// Whether this statement is either an `EXPLAIN` or an `EXPLAIN QUERY PLAN`
  /// statement.
  ///
  /// This uses `sqlite3_stmt_isexplain`, which is documented here:
  /// https://www.sqlite.org/c3ref/stmt_isexplain.html
  bool get isExplain;

  /// {@template pkg_sqlite3_stmt_execute}
  /// Executes this statement, ignoring result rows if there are any.
  ///
  /// If the [parameters] list does not match the amount of parameters in the
  /// original SQL statement ([parameterCount]), an [ArgumentError] will be
  /// thrown.
  /// See [StatementParameters] for a list of types supported by this library.
  /// If sqlite3 reports an error while running this statement, a
  /// [SqliteException] will be thrown.
  ///
  /// To run a statement and also obtaining returned rows, use [selectWith] or
  /// [iterateWith]. It is safe to call these methods on statements that aren't
  /// `SELECT` statements (such as writes with a `RETURNING` clause) too.
  /// {@endtemplate}
  void executeWith(StatementParameters parameters);

  /// {@template pkg_sqlite3_stmt_select}
  /// Selects all rows into a [ResultSet].
  ///
  /// If the [parameters] list does not match the amount of parameters in the
  /// original SQL statement ([parameterCount]), an [ArgumentError] will be
  /// thrown.
  /// See [StatementParameters] for a list of types supported by this library.
  /// If sqlite3 reports an error while running this statement, a
  /// [SqliteException] will be thrown.
  ///
  /// This statement doesn't have to be a `SELECT` statement for [selectWith] to
  /// be useful - writes with `RETURNING` clauses also return rows which can
  /// be fetched via [selectWith].
  /// {@endtemplate}
  ResultSet selectWith(StatementParameters parameters);

  /// {@template pkg_sqlite3_stmt_iterate}
  /// Starts selecting rows by running this prepared statement with the given
  /// [parameters].
  ///
  /// If the [parameters] list does not match the amount of parameters in the
  /// original SQL statement ([parameterCount]), an [ArgumentError] will be
  /// thrown.
  /// See [StatementParameters] for a list of types supported by this library.
  ///
  /// If sqlite3 reports an error while running this statement, it will be
  /// thrown by a call to [Iterator.moveNext].
  ///
  /// The iterator returned here will become invalid with the next call to a
  /// method that runs this statement ([execute], [executeWith], [select],
  /// [selectWith], [selectCursor], [iterateWith]).
  /// {@endtemplate}
  IteratingCursor iterateWith(StatementParameters parameters);

  /// {@macro pkg_sqlite3_stmt_execute}
  void execute([List<Object?> parameters = const <Object>[]]) {
    return executeWith(StatementParameters(parameters));
  }

  /// {@macro pkg_sqlite3_stmt_execute}
  ///
  /// Unlike [execute], which binds parameters by their index, [executeMap]
  /// binds parameters by their name.
  /// For instance, a SQL query `SELECT :foo, @bar;` has two named parameters
  /// (`:foo` and `@bar`) that can occur as keys in [parameters].
  @Deprecated('Use executeWith(StatementParameters.named) instead')
  void executeMap(Map<String, Object?> parameters) {
    return executeWith(StatementParameters.named(parameters));
  }

  /// {@macro pkg_sqlite3_stmt_select}
  ResultSet select([List<Object?> parameters = const <Object>[]]) {
    return selectWith(StatementParameters(parameters));
  }

  /// {@macro pkg_sqlite3_stmt_select}
  ///
  /// Similar to [executeMap], parameters are bound by their name instead of
  /// their index.
  @Deprecated('Use selectWith(StatementParameters.named) instead')
  ResultSet selectMap(Map<String, Object?> parameters) {
    return selectWith(StatementParameters.named(parameters));
  }

  /// {@macro pkg_sqlite3_stmt_iterate}
  IteratingCursor selectCursor([List<Object?> parameters = const <Object>[]]) {
    return iterateWith(StatementParameters(parameters));
  }

  /// Resets this statement to be excuted again.
  ///
  /// You typically don't need to call [reset] manually as it is called for you
  /// internally when [select] or [execute] called multiple times.
  /// However, [reset] removes all active cursors on this statement, which can
  /// be useful if a statement is re-used across longer periods of time.
  ///
  /// See also:
  ///  - [sqlite3_reset]: https://www.sqlite.org/c3ref/reset.html
  void reset();

  /// Disposes this statement and releases associated memory.
  @Deprecated('Use close() instead')
  void dispose();

  /// Closes this prepared statement.
  ///
  /// On native platforms, a native finalizer will also close statements
  /// automatically. On the web, finalizers are less reliable. For this reason,
  /// closing statements explicitly is still recommended.
  ///
  /// See also:
  ///  - `sqlite3_finalize`: https://www.sqlite.org/c3ref/finalize.html
  void close();
}

/// Unsafe, raw access to a prepared statement.
///
/// [CommonPreparedStatement] automatically converts columns to Dart objects
/// based on their [columnType] and uses high-level types like lists to
/// represent parameters and results.
///
/// In some cases, it may be more efficient to call the underlying `sqlite3_`
/// methodsmdirectly. This class provides methods mapping directly to raw SQLite
/// C function calls, with no additional checks or implicit conversions.
///
/// Typically, this API would be used by:
///
/// 1. Calling `bind` methods to bind prepared statement parameters.
/// 2. While [step] returns `true`,
///    - call [columnType] and other `column` methods to read values.
/// 3. Call [CommonPreparedStatement.reset].
///
/// On the web, this can also be used to bind JavaScript `BigInt` values to
/// statements via [WasmRawPreparedStatement].
///
/// None of these methods may be called after a statement is
/// [CommonPreparedStatement.close]d. Unlike [CommonPreparedStatement] methods
/// which validate that invariant, calling raw methods on finalized statements
/// is an unchecked use-after-free.
///
/// {@category common}
@experimental
extension type RawPreparedStatement._(StatementImplementation _stmt) {
  /// Calls `sqlite3_bind_null` with the 1-based index.
  void bindNull(int index) {
    handleBindRc(rawStatement.sqlite3_bind_null(index));
  }

  /// Calls `sqlite3_bind_int64` with the 1-based index and the target value.
  void bindInt64(int index, int value) {
    handleBindRc(rawStatement.sqlite3_bind_int64(index, value));
  }

  /// Calls `sqlite3_bind_double` with the 1-based index and the target value.
  void bindDouble(int index, double value) {
    handleBindRc(rawStatement.sqlite3_bind_double(index, value));
  }

  /// Calls `sqlite3_bind_text` with the 1-based index and the target value.
  void bindText(int index, String value) {
    handleBindRc(rawStatement.sqlite3_bind_text(index, value));
  }

  /// Calls `sqlite3_bind_blob64` with the 1-based index and the target value.
  void bindBlob(int index, List<int> value) {
    handleBindRc(rawStatement.sqlite3_bind_blob64(index, value));
  }

  /// Calls `sqlite3_step`.
  ///
  /// This returns true if a row was returned, false if the end of the statement
  /// cursor was reached. For other return values, throws a [SqliteException].
  bool step() {
    final rc = _stmt.stepExternalCursor();
    return switch (rc) {
      SqlError.SQLITE_ROW => true,
      SqlError.SQLITE_DONE || SqlError.SQLITE_OK => false,
      _ => _stmt.throwStatementException(rc, 'step'),
    };
  }

  /// Calls `sqlite3_column_count`, returning the amount of columns of this
  /// prepared statement.
  int get columnCount {
    return rawStatement.sqlite3_column_count();
  }

  /// Calls `sqlite3_column_name` with the given index.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  String columnName(int index) {
    return rawStatement.sqlite3_column_name(index);
  }

  /// If supported by the current SQLite build, calls
  /// `sqlite3_column_table_name` with the given index.
  String? columnTableName(int index) {
    final stmt = rawStatement;
    if (!stmt.supportsReadingTableNameForColumn) return null;

    return stmt.sqlite3_column_table_name(index);
  }

  /// Calls `sqlite3_column_type`, returning the type of a column.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  ///
  /// See also: https://sqlite.org/c3ref/column_blob.html
  SqlType columnType(int index) {
    return rawStatement.sqlite3_column_type(index);
  }

  /// Calls `sqlite3_column_int64` with the given index.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  int columnInt64(int index) {
    return rawStatement.sqlite3_column_int64(index);
  }

  /// Calls `sqlite3_column_double` with the given index.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  double columnDouble(int index) {
    return rawStatement.sqlite3_column_double(index);
  }

  /// Calls `sqlite3_column_text` with the given index.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  String columnText(int index) {
    return rawStatement.sqlite3_column_text(index);
  }

  /// Calls `sqlite3_column_blob` with the given index.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  Uint8List columnBlob(int index) {
    return rawStatement.sqlite3_column_bytes(index);
  }
}

@internal
extension InternalRawPreparedStatement on RawPreparedStatement {
  static RawPreparedStatement wrap(StatementImplementation stmt) {
    return RawPreparedStatement._(stmt);
  }

  RawSqliteStatement get rawStatement => _stmt.statement;

  void handleBindRc(int rc) {
    if (rc != SqlError.SQLITE_OK) {
      _stmt.throwStatementException(rc, 'binding parameter');
    }
  }
}

/// A set of values that can be used to bind [parameters] in a SQL query.
///
/// Parameters are placeholder values in SQL that can safely be bound to values
/// later without a risk of SQL injection attacks.
/// Depending on the syntax used to declare a parameter, it may make sense to
/// pass parameters by their index or by name. The different constructors of
/// this class can be used to control how parameters are passed.
///
/// This package supports binding [int], [BigInt], [String], [double], `List<int>`
/// and `null` values by default. For custom values, such as those using the
/// [pointer-binding](https://www.sqlite.org/bindptr.html) interface provided by
/// `sqlite3`, [CustomStatementParameter] can be implemented and passed as a
/// parameter as well.
///
/// {@category common}
///
/// [parameters]: https://www.sqlite.org/lang_expr.html#varparam
sealed class StatementParameters {
  /// Convenience factory to use when no parameters should be passed.
  const factory StatementParameters.empty() = IndexedParameters.empty;

  /// Passes parameters by their variable number.
  const factory StatementParameters(List<Object?> parameters) =
      IndexedParameters;

  /// Passes variables by their name.
  ///
  /// For instance, the statement `SELECT * FROM users WHERE id = :id` could be
  /// bound with `StatementParameters.named({':a': 42})`.
  const factory StatementParameters.named(Map<String, Object?> parameters) =
      NamedParameters;

  /// Passes variables by invoking a callback responsible for using a native
  /// statement handle to bind parameters.
  ///
  /// Other constructors validate parameters, making them harder to misuse. In
  /// special cases where that doesn't work, this constructor can be used to
  /// indicate that you are fully responsible for binding parameters and don't
  /// need any validation checks.
  const factory StatementParameters.bindCustom(
    void Function(CommonPreparedStatement stmt) bind,
  ) = CustomParameters;
}

@internal
class IndexedParameters implements StatementParameters {
  final List<Object?> parameters;

  const IndexedParameters(this.parameters);

  const IndexedParameters.empty() : parameters = const [];
}

@internal
class NamedParameters implements StatementParameters {
  final Map<String, Object?> parameters;

  const NamedParameters(this.parameters);
}

@internal
class CustomParameters implements StatementParameters {
  final void Function(CommonPreparedStatement) bind;

  const CustomParameters(this.bind);
}

/// A parameter passed to prepared statements that decides how it gets mapped to
/// SQL in [applyTo].
///
/// Implementing and using this class is rarely useful, as this package supports
/// standard types supported by `sqlite3` directly.
/// For advanced APIs, such as the [pointer-passing](https://www.sqlite.org/bindptr.html)
/// interface that can't directly be represented in a high-level Dart interface,
/// this class can be used to manually bind a value.
///
/// {@category common}
abstract interface class CustomStatementParameter {
  /// Applies this custom parameter to the [statement] at the variable index
  /// [index].
  ///
  /// On native platforms, an implementation can safely cast the `statement` to
  /// a `PreparedStatement` (from `package:sqlite3/sqlite3.dart`) and use the
  /// `PreparedStatement.handle` to call `sqlite3_bind_*` manually.
  void applyTo(CommonPreparedStatement statement, int index);
}
