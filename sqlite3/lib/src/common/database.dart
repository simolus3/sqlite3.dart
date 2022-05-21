import 'package:meta/meta.dart';

import 'functions.dart';
import 'result_set.dart';
import 'statement.dart';

/// An opened sqlite3 database.
abstract class CommonDatabase {
  /// The application defined version of this database.
  int get userVersion {
    final stmt = prepare('PRAGMA user_version;');
    final result = stmt.select();

    final version = result.first.columnAt(0) as int;
    stmt.dispose();
    return version;
  }

  set userVersion(int value) {
    execute('PRAGMA user_version = $value;');
  }

  /// Returns the row id of the last inserted row.
  int get lastInsertRowId;

  /// The amount of rows affected by the last `INSERT`, `UPDATE` or `DELETE`
  /// statement.
  int getUpdatedRows();

  /// An async stream of data changes happening on this database.
  ///
  /// Listening to this stream will register an "update hook" on the native
  /// database. Each update that sqlite3 reports through that hook will then
  /// be added to the stream.
  ///
  /// Note that the stream reports updates _asynchronously_, e.g. one event
  /// loop iteration after sqlite reports them.
  /// Also, be aware that not every update to the database will be reported.
  /// In particular, updates to internal system tables like `sqlite_sequence`
  /// are not reported. Further, updates to `WITHOUT ROWID` tables or truncating
  /// deletes (without a `WHERE` clause) will not report updates either.
  ///
  /// See also:
  ///  - [Data Change Notification Callbacks](https://www.sqlite.org/c3ref/update_hook.html)
  @experimental
  Stream<SqliteUpdate> get updates;

  /// Executes the [sql] statement with the provided [parameters] and ignores
  /// the result.
  void execute(String sql, [List<Object?> parameters = const []]);

  /// Prepares the [sql] select statement and runs it with the provided
  /// [parameters].
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    final stmt = prepare(sql);
    final result = stmt.select(parameters);
    stmt.dispose();
    return result;
  }

  /// Compiles the [sql] statement to execute it later.
  ///
  /// The [persistent] flag can be used as a hint to the query planner that the
  /// statement will be retained for a long time and probably reused many times.
  /// Without this flag, sqlite assumes that the prepared statement will be used
  /// just once or at most a few times before [CommonPreparedStatement.dispose]
  /// is called.
  /// If [vtab] is disabled (it defaults to `true`) and the statement references
  /// a virtual table, [prepare] throws an exception.
  /// For more information on the optional parameters, see
  /// [the sqlite documentation](https://www.sqlite.org/c3ref/c_prepare_normalize.html)
  /// If [checkNoTail] is enabled (it defaults to `false`) and the [sql] string
  /// contains trailing data, an exception will be thrown and the statement will
  /// not be executed.
  CommonPreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true, bool checkNoTail = false});

  /// Compiles multiple statements from [sql] to be executed later.
  ///
  /// Unlike [prepare], which can only compile a single statement,
  /// [prepareMultiple] will return multiple statements if the source [sql]
  /// string contains more than one statement.
  /// For example, calling [prepareMultiple] with `SELECT 1; SELECT 2;` will
  /// return `2` prepared statements.
  ///
  /// For the [persistent] and [vtab] parameters, see [prepare].
  List<CommonPreparedStatement> prepareMultiple(String sql,
      {bool persistent = false, bool vtab = true});

  /// Creates a collation that can be used from sql queries sent against
  /// this database.
  ///
  /// The [name] defines the (case insensitive) name of the collating in
  /// sql. The utf8 encoding of [name] must not exceed a length of 255
  /// bytes.
  ///
  /// The [function] can be any Dart closure, it's not restricted to top-level
  /// functions supported by `Pointer.fromFunction`. For more details on how
  /// the sql function behaves, see the documentation on [CollatingFunction].
  /// As it is a compare function, the [function] must return an integer value, and
  /// receives two string parameters (**A** & **B**). [function] will return 0
  /// if **A** and **B**
  /// are considered equals. A negative value is returned if **A** is less than **B**,
  /// but a positive if **A** is greater than **B**.
  ///
  ///
  ///
  /// For more information, see https://www.sqlite.org/c3ref/create_collation.html.
  void createCollation({
    required String name,
    required CollatingFunction function,
  });

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
  /// The [function] can be any Dart closure, it's not restricted to top-level
  /// functions supported by `Pointer.fromFunction`. For more details on how
  /// the sql function behaves, see the documentation on [ScalarFunction].
  ///
  /// To register aggregate or window functions, see [createAggregateFunction].
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
  ///
  /// If the given [function] implements the [WindowFunction] interface, a
  /// window function is registered internally. Window functions support being
  /// used in `OVER` expressions in sqlite3. For more information on writing
  /// window functions in Dart, see the [WindowFunction] class. For details
  /// on user-defined window functions in general, see sqlite3's documentation:
  /// https://www.sqlite.org/windowfunctions.html#udfwinfunc
  void createAggregateFunction<V>({
    required String functionName,
    required AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
  });

  /// Waits for the data to be written to persistent storage
  Future<void> flush();

  /// Closes this database and releases associated resources.
  void dispose();
}

/// The kind of an [SqliteUpdate] received through a [CommonDatabase.updates]
/// stream.
enum SqliteUpdateKind {
  /// Notification for a new row being inserted into the database.
  insert,

  /// Notification for a row being updated.
  update,

  /// Notification for a row being deleted.
  delete
}

/// A data change notification from sqlite.
class SqliteUpdate {
  /// The kind of write being reported.
  final SqliteUpdateKind kind;

  /// The table on which the update has happened.
  final String tableName;

  /// The id of the inserted, modified or deleted row.
  final int rowId;

  SqliteUpdate(this.kind, this.tableName, this.rowId);
}
