import 'dart:async';

import 'functions.dart';
import 'result_set.dart';
import 'statement.dart';
import 'constants.dart';

/// An opened sqlite3 database.
///
/// {@category common}
abstract class CommonDatabase {
  /// Configuration for the database connection.
  ///
  /// __Note__: On the web, the [DatabaseConfig] class only works when using a
  /// version of `sqlite3.wasm` shipped with version 2.1.0 of the `sqlite3`
  /// Dart package. In previous WASM builds, all setters on the config will
  /// throw an exception.
  DatabaseConfig get config;

  /// The application defined version of this database.
  abstract int userVersion;

  /// The row id of the most recent successful insert statement on this database
  /// connection.
  ///
  /// This does not consider `WITHOUT ROWID` tables and won't reliably detect
  /// inserts made by triggers. For details, see the [sqlite3 docs](https://sqlite.org/c3ref/last_insert_rowid.html).
  int get lastInsertRowId;

  /// The amount of rows inserted, updated or deleted by the last `INSERT`,
  /// `UPDATE` or `DELETE` statement, respectively.
  ///
  /// For more details, see the [sqlite3 docs](https://sqlite.org/c3ref/changes.html).
  int get updatedRows;

  /// The amount of rows affected by the last `INSERT`, `UPDATE` or `DELETE`
  /// statement.
  @Deprecated('Use updatedRows instead')
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
  ///  - [updatesSync], a synchronous stream.
  Stream<SqliteUpdate> get updates;

  /// A _synchronous_ stream of data changes happening on this database.
  ///
  /// This stream behaves similarly to [updates], except that listeners are
  /// invoked synchronously (before the update completes).
  ///
  /// The purpose of this stream is to avoid a large internal buffer when a
  /// transaction updates a large amount of rows - instead, the updates can be
  /// handled one-by-one with this.
  ///
  /// It is crucial that listeners on this stream don't modify the database.
  Stream<SqliteUpdate> get updatesSync;

  /// The [VoidPredicate] that is used to filter out transactions before commiting.
  ///
  /// This is run before every commit, i.e. before the end of an explicit
  /// transaction and before the end of an implicit transactions created by
  /// an insert / update / delete operation.
  ///
  /// If the filter returns `false`, the commit is converted into a rollback.
  ///
  /// The function should not do anything that modifies the database connection,
  /// e.g. run SQL statements, prepare statements or step.
  ///
  /// See also:
  ///   - [Commit Hooks](https://www.sqlite.org/c3ref/commit_hook.html)
  VoidPredicate? get commitFilter;
  set commitFilter(VoidPredicate? commitFilter);

  /// An async stream that fires after each commit.
  ///
  /// Listening to this stream will register a "commit hook" on the native
  /// database. Each commit that sqlite3 reports through that hook will then
  /// be added to the stream.
  ///
  /// Note that the stream reports updates _asynchronously_, e.g. one event
  /// loop iteration after sqlite reports them.
  ///
  /// Also note this works in conjunction with `commitFilter`. If the filter
  /// function is not null and returns `false`, the commit will not occur and
  /// this stream will not fire.
  ///
  /// See also:
  ///   - [Commit Hooks](https://www.sqlite.org/c3ref/commit_hook.html)
  Stream<void> get commits;

  /// An async stream that fires after each rollback.
  ///
  /// Listening to this stream will register a "rollback hook" on the native
  /// database. Each rollback that sqlite3 reports through that hook will then
  /// be added to the stream.
  ///
  /// Note that the stream reports updates _asynchronously_, e.g. one event
  /// loop iteration after sqlite reports them.
  ///
  /// See also:
  ///   - [Commit Hooks](https://www.sqlite.org/c3ref/commit_hook.html)
  Stream<void> get rollbacks;

  /// The trace callback currently registered on this database, if any.
  ///
  /// The callback is invoked synchronously for statement trace events, as
  /// reported by [sqlite3_trace_v2](https://www.sqlite.org/c3ref/trace_v2.html).
  /// It runs while the traced statement is running - in particular, it is
  /// invoked before the call running the statement (e.g. [execute] or
  /// [select]) returns. Events are always reported in the order in which they
  /// occur; use [SqliteTraceWithStatement.statementAddress] to correlate
  /// events belonging to the same statement.
  ///
  /// Only the event categories enabled through [SqliteTraceCallback.statement],
  /// [SqliteTraceCallback.row] and [SqliteTraceCallback.profile] are reported.
  /// As this property mirrors the underlying C interface, a database only
  /// supports a single trace callback: assigning a new callback (or enabling
  /// different categories) replaces the previous registration. Applications
  /// observing the same database from multiple places can fan events out in
  /// their callback.
  ///
  /// As the callback runs as part of running statements, it must not modify
  /// the database. Exceptions thrown by the callback are ignored (they cannot
  /// be propagated through sqlite's native frames); the value it returns is
  /// passed back to sqlite, which currently ignores it. Note that durations
  /// reported by [SqliteTraceProfile] events include the overhead of invoking
  /// the callback itself.
  ///
  /// While a callback is registered, statements report events by invoking it
  /// synchronously - one invocation per enabled event. In particular, enabling
  /// [SqliteTraceCallback.row] adds overhead proportional to the number of
  /// rows returned by statements, so unless row-level events are needed, prefer
  /// a smaller set of categories such as [SqliteTraceCallback.statement] and
  /// [SqliteTraceCallback.profile].
  ///
  /// Assigning a callback throws an [UnsupportedError] if the sqlite3 library
  /// in use doesn't support tracing, e.g. because an outdated `sqlite3.wasm`
  /// bundle is being used. All native sqlite3 libraries shipped with releases
  /// of this package support tracing.
  SqliteTraceCallback? get trace;

  /// Registers [callback] as this database's trace callback, replacing any
  /// previous registration.
  ///
  /// Assigning `null` removes the callback, after which statements no longer
  /// report trace events. Doing so is a no-op if no callback is registered or
  /// if the sqlite3 library in use does not support tracing at all.
  ///
  /// See [trace] for the semantics of registered callbacks.
  set trace(SqliteTraceCallback? callback);

  /// Executes the [sql] statement(s) with the provided [parameters], ignoring
  /// any rows returned by the statement(s).
  ///
  /// For the types supported in [parameters], see [StatementParameters].
  /// To view rows returned by a statement, run it with [select]. Statements
  /// that aren't `SELECT`s in SQL but still return rows (such as updates with
  /// a `RETURNING` clause) can still be safely executed with [select].
  ///
  /// When no [parameters] are passed to [execute], [sql] is allowed to contain
  /// multiple SQL statements (separated by a semicolon). Those statements will
  /// be executed in order, but [execute] will not start a transaction for them
  /// automatically. If any statement fails, that exception will be thrown and
  /// subsequent statements will not be executed.
  void execute(String sql, [List<Object?> parameters = const []]);

  /// Prepares the [sql] statement and runs it with the provided [parameters],
  /// returning all rows returned by the statement.
  ///
  /// For the types supported in [parameters], see [StatementParameters].
  /// The statement doesn't have to be an SQL `SELECT` statement. Any statement
  /// that returns rows (e.g. writes with a `RETURNING` clause) can be executed
  /// with [select].
  ///
  /// This method fully runs the statement, buffers all rows and then returns
  /// them at once in a [ResultSet]. This package also supports stepping through
  /// a result set row-by-row. To do that, first prepare the statement with
  /// [prepare] and then call [CommonPreparedStatement.iterateWith].
  ResultSet select(String sql, [List<Object?> parameters = const []]);

  /// Compiles the [sql] statement to execute it later.
  ///
  /// The [persistent] flag can be used as a hint to the query planner that the
  /// statement will be retained for a long time and probably reused many times.
  /// Without this flag, sqlite assumes that the prepared statement will be used
  /// just once or at most a few times before [CommonPreparedStatement.close]
  /// is called.
  /// If [vtab] is disabled (it defaults to `true`) and the statement references
  /// a virtual table, [prepare] throws an exception.
  /// For more information on the optional parameters, see
  /// [the sqlite documentation](https://www.sqlite.org/c3ref/c_prepare_normalize.html)
  /// If [checkNoTail] is enabled (it defaults to `false`) and the [sql] string
  /// contains trailing data, an exception will be thrown and the statement will
  /// not be executed.
  CommonPreparedStatement prepare(
    String sql, {
    bool persistent = false,
    bool vtab = true,
    bool checkNoTail = false,
  });

  /// Compiles multiple statements from [sql] to be executed later.
  ///
  /// Unlike [prepare], which can only compile a single statement,
  /// [prepareMultiple] will return multiple statements if the source [sql]
  /// string contains more than one statement.
  /// For example, calling [prepareMultiple] with `SELECT 1; SELECT 2;` will
  /// return `2` prepared statements.
  ///
  /// For the [persistent] and [vtab] parameters, see [prepare].
  List<CommonPreparedStatement> prepareMultiple(
    String sql, {
    bool persistent = false,
    bool vtab = true,
  });

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
  ///
  /// The [subtype] flag (defaults to `false`) indicates that the function can
  /// receive subtypes in arguments (meaning that [SqliteArguments.subtypeOf]
  /// can be used) and that the function can return values with subtypes (by
  /// returning an [SubtypedValue]).
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
    bool subtype = false,
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
    bool subtype = false,
  });

  /// Installs a function to invoke whenever an attempt is made to access a
  /// database table when another thread or process has the table locked.
  ///
  /// The argument passed to the [handler] is the amount of times it has
  /// previously been invoked for the same locking event.
  /// The handler should return `true` if SQLite should make another attempt to
  /// access the database, or `false` if SQLite should stop making attempts and
  /// return `SQLITE_BUSY`.
  ///
  /// Note that using the `busy_timeout` pragma will overwrite this handler.
  ///
  /// See also: https://www.sqlite.org/c3ref/busy_handler.html
  set busyHandler(bool Function(int count)? handler);

  /// Checks whether the connection is in autocommit mode. The connection is in
  /// autocommit by default, except when inside a transaction.
  ///
  /// For details, see https://www.sqlite.org/c3ref/get_autocommit.html
  bool get autocommit;

  /// Returns runtime status information about this connection, such as the
  /// amount of memory used by its page cache ([StatusParameter.cacheUsed]).
  ///
  /// Not every [option] reports a meaningful `highwater` value, see the
  /// documentation of the options for details. When [reset] is set, the
  /// highest value is reset after reading it.
  ///
  /// This requires SQLite 3.51.0 or newer, as it uses `sqlite3_db_status64`.
  /// With older SQLite libraries or incompatible `sqlite3.wasm` bundles, this
  /// throws.
  ///
  /// See https://sqlite.org/c3ref/db_status.html
  ({int current, int highwater}) status(
    StatusParameter option, {
    bool reset = false,
  });

  /// Closes this database and releases associated resources.
  @Deprecated('Call close() instead')
  void dispose();

  /// Closes this database and releases associated resources.
  ///
  /// On native platforms, a native finalizer will also close the connection
  /// automatically. On the web, finalizers are less reliable. For this reason,
  /// closing databases explicitly is still recommended.
  void close();
}

/// The kind of an [SqliteUpdate] received through a [CommonDatabase.updates]
/// stream.
///
/// {@category common}
enum SqliteUpdateKind {
  // Note: Changing the order of these fields is a breaking change, as they're
  // used in the sqlite3_web protocol.

  /// Notification for a new row being inserted into the database.
  insert(SQLITE_INSERT),

  /// Notification for a row being updated.
  update(SQLITE_UPDATE),

  /// Notification for a row being deleted.
  delete(SQLITE_DELETE);

  /// The raw code to identify this update kind.
  final int code;

  const SqliteUpdateKind(this.code);

  /// Attempts to extract a [SqliteUpdateKind] from the raw [flags].
  static SqliteUpdateKind? fromCode(int code) {
    return switch (code) {
      SQLITE_INSERT => insert,
      SQLITE_UPDATE => update,
      SQLITE_DELETE => delete,
      _ => null,
    };
  }
}

/// A data change notification from sqlite.
///
/// {@category common}
final class SqliteUpdate {
  /// The kind of write being reported.
  final SqliteUpdateKind kind;

  /// The table on which the update has happened.
  final String tableName;

  /// The id of the inserted, modified or deleted row.
  final int rowId;

  SqliteUpdate(this.kind, this.tableName, this.rowId);

  @override
  int get hashCode => Object.hash(kind, tableName, rowId);

  @override
  bool operator ==(Object other) {
    return other is SqliteUpdate &&
        other.kind == kind &&
        other.tableName == tableName &&
        other.rowId == rowId;
  }

  @override
  String toString() {
    return 'SqliteUpdate: $kind on $tableName, rowid = $rowId';
  }
}

/// A callback for trace events, as registered through [CommonDatabase.trace].
///
/// {@category common}
final class SqliteTraceCallback {
  /// Creates a trace callback that is invoked for the event categories
  /// enabled through [statement], [row] and [profile].
  ///
  /// At least one of these categories must be enabled.
  SqliteTraceCallback(
    this.onTrace, {
    this.statement = true,
    this.row = true,
    this.profile = true,
  });

  /// The function invoked synchronously while the traced statement is
  /// running.
  ///
  /// It must return `0`: sqlite currently ignores the value returned by
  /// trace callbacks, but reserves it for future use. Applications must not
  /// modify the database from the callback.
  final int Function(SqliteTrace trace) onTrace;

  /// Whether to report statements starting to run, as [SqliteTraceStatement]
  /// events.
  final bool statement;

  /// Whether to report rows returned by a running statement, as
  /// [SqliteTraceRow] events.
  final bool row;

  /// Whether to report statements finishing to run, as [SqliteTraceProfile]
  /// events.
  final bool profile;
}

/// A trace event reported by [CommonDatabase.trace].
///
/// {@category common}
sealed class SqliteTrace {}

/// A [SqliteTrace] event that belongs to a single prepared statement.
///
/// {@category common}
abstract interface class SqliteTraceWithStatement {
  /// An opaque address identifying the native statement object this event
  /// belongs to. It is stable for the duration of the statement's execution,
  /// so it can be used to correlate the events reported for it.
  int get statementAddress;
}

/// A statement starting to run, as reported by
/// [CommonDatabase.trace].
///
/// {@category common}
final class SqliteTraceStatement extends SqliteTrace
    implements SqliteTraceWithStatement {
  /// The unexpanded SQL text of the statement, or `null` when sqlite does
  /// not provide SQL text (e.g. for internal statements).
  final String? sql;

  @override
  final int statementAddress;

  SqliteTraceStatement(this.sql, this.statementAddress);

  @override
  String toString() =>
      'SqliteTraceStatement: ${sql ?? '<no sql>'} ($statementAddress)';
}

/// A statement finishing to run, as reported by
/// [CommonDatabase.trace].
///
/// {@category common}
final class SqliteTraceProfile extends SqliteTrace
    implements SqliteTraceWithStatement {
  /// How long the statement took to run.
  ///
  /// Note that this duration includes the overhead of invoking trace
  /// callbacks reported while the statement was running.
  final Duration duration;

  @override
  final int statementAddress;

  SqliteTraceProfile(this.duration, this.statementAddress);

  @override
  String toString() => 'SqliteTraceProfile: $duration ($statementAddress)';
}

/// A row being returned by a running statement, as reported by
/// [CommonDatabase.trace].
///
/// {@category common}
final class SqliteTraceRow extends SqliteTrace
    implements SqliteTraceWithStatement {
  @override
  final int statementAddress;

  SqliteTraceRow(this.statementAddress);

  @override
  String toString() => 'SqliteTraceRow ($statementAddress)';
}

/// Make configuration changes to the database connection.
///
/// More information: https://www.sqlite.org/c3ref/db_config.html
/// Available options are documented in https://www.sqlite.org/c3ref/c_dbconfig_defensive.html
///
/// {@category common}
abstract base class DatabaseConfig {
  /// Update configuration that accepts an int value.
  /// Would throw when the internal C call returns a non-zero value.
  void setIntConfig(int key, int configValue);

  /// Enable or disable SQLite support for double quotes as string literals.
  ///
  /// More information: https://www.sqlite.org/compile.html#dqs
  set doubleQuotedStringLiterals(bool value) {
    final dqsValue = value ? 1 : 0;
    setIntConfig(SQLITE_DBCONFIG_DQS_DML, dqsValue);
    setIntConfig(SQLITE_DBCONFIG_DQS_DDL, dqsValue);
  }
}
