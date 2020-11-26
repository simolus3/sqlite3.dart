import 'dart:ffi';
import 'package:sqlite3/src/api/result_set.dart';

import 'functions.dart';
import 'statement.dart';

/// An opened sqlite3 database.
abstract class Database {
  /// The application defined version of this database.
  int get userVersion;
  set userVersion(int version);

  /// Returns the row id of the last inserted row.
  int get lastInsertRowId;

  /// The native database connection handle from sqlite.
  ///
  /// This returns a pointer towards the opaque sqlite3 structure as defined
  /// [here](https://www.sqlite.org/c3ref/sqlite3.html).
  Pointer<void> get handle;

  /// The amount of rows affected by the last `INSERT`, `UPDATE` or `DELETE`
  /// statement.
  int getUpdatedRows();

  /// Executes the [sql] statement and ignores the result.
  void execute(String sql);

  /// Prepares the [sql] select statement and runs it with the provided
  /// [parameters].
  ResultSet select(String sql, [List<Object?> parameters]);

  /// Compiles the [sql] statement to execute it later.
  ///
  /// The [persistent] flag can be used as a hint to the query planner that the
  /// statement will be retained for a long time and probably reused many times.
  /// Without this flag, sqlite assumes that the prepared statement will be used
  /// just once or at most a few times before [PreparedStatement.dispose] is
  /// called.
  /// If [vtab] is disabled (it defaults to `true`) and the statement references
  /// a virtual table, [prepare] throws an exception.
  /// For more information on the optional parameters, see
  /// [the sqlite documentation](https://www.sqlite.org/c3ref/c_prepare_normalize.html)
  PreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true});

  /// Creates a scalar function that can be called from sql queries sent against
  /// this database.
  ///
  /// The [functionName] defines the (case insensitive) name of the function in
  /// sql. The utf8 encoding of [functionName] must not exceed a length of 255
  /// bytes.
  ///
  /// {@template sqlite3_function_flags}
  /// The [argumentCount] parameter can be used to declare how many arguments a
  /// function supports. If you need a function that can use multiple argument
  /// counts, you can call [createFunction] multiple times.
  /// The [deterministic] flag (defaults to `false`) can be set to indicate that
  /// the function always gives the same output when the input parameters are
  /// the same. This is a requirement for functions that are used in generated
  /// columns or partial indexes. It also allows the query planner for optimize
  /// by factoring invocations out of inner loops.
  /// The [directOnly] flag (defaults to `true`) is a security measure. When
  /// enabled, the function may only be invoked form top-level SQL, and cannot
  /// be used in VIEWs or TRIGGERs nor in schema structures (such as CHECK,
  /// DEFAULT, etc.). When [directOnly] is set to `false`, the function might
  /// be invoked when opening a malicious database file. sqlite3 recommends
  /// this flag for all application-defined functions, especially if they have
  /// side-effects or if they could potentially leak sensitive information.
  /// {@endtemplate}
  ///
  /// The [function] can be any Dart closure, it's not restricted to functions
  /// that would be supported by [Pointer.fromFunction]. For more details on how
  /// the sql function behaves, see the documentation on [ScalarFunction].
  ///
  /// For more information, see https://www.sqlite.org/appfunc.html.
  void createFunction({
    required String functionName,
    required ScalarFunction function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
  });

  /// Creates an application-defined aggregate function that can be used from
  /// sql queries sent against this database.
  ///
  /// {@macro sqlite3_function_flags}
  ///
  /// For more details on how to write aggregate functions (including an
  /// example), see the documentation of [AggregateFunction].
  void createAggregateFunction<V>({
    required String functionName,
    required AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
  });

  /// Closes this database and releases associated resources.
  void dispose();
}
