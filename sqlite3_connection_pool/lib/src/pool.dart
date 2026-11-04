/// @docImport 'abort_exception.dart';
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'connection.dart';
import 'mutex.dart';
import 'raw.dart';

/// The result of calling [ConnectionLease.execute]. This provides access to the
/// `autocommit` state (indicating whether the database is in a transaction) as
/// well as the changes and last insert rowid.
typedef ExecuteResult = ({bool autoCommit, int changes, int lastInsertRowId});

/// A pool giving out SQLite connections asynchronously.
///
/// Pools are identified by name and managed by native code, which means that
/// even two isolates without a communication channel can safely share pools.
///
/// To open a pool, use [SqliteConnectionPool.open]. Pools are closed with
/// [SqliteConnectionPool.close] (or by just not referencing them any longer),
/// but the underlying connections are only closed once all pool instances
/// across isolates are closed.
///
/// You can query pools directly, [readQuery] runs a read-only select statement
/// and [execute] runs writes (including writes with a `RETURNING` statement).
///
/// Additionally, [reader] and [writer] return a [ConnectionLease] which allows
/// running multiple statements on the same connection (useful e.g. for
/// transactions). Obtained leases must be returned to the pool with
/// [ConnectionLease.returnLease].
///
/// Finally, [exclusiveAccess] gives you exclusive access to the pool. This is
/// useful in some cases where a schema update needs to be applied to read
/// connections explicitly.
final class SqliteConnectionPool {
  /// The name identifying this pool.
  ///
  /// In a Dart process (across all isolates), there will at most be one pool
  /// with a given name at the same time. Multiple instances with the same name
  /// will always share the same underlying pool.
  final String name;
  final RawSqliteConnectionPool _raw;
  final StreamController<List<String>> _updatedTables =
      StreamController.broadcast();
  RawReceivePort? _receiveTableUpdates;

  Future<void>? _closing;

  SqliteConnectionPool._(this.name, this._raw) {
    _updatedTables.onListen = () {
      assert(_receiveTableUpdates == null);
      final port = _receiveTableUpdates = RawReceivePort(
        (List<dynamic> msg) => _updatedTables.add(msg.cast()),
        'Receive table updates',
      );
      port.keepIsolateAlive = false;
      _raw.addUpdateListener(port.sendPort);
    };
    _updatedTables.onCancel = () {
      if (_receiveTableUpdates case final port?) {
        port.close();
        _raw.removeUpdateListener(port.sendPort);
        _receiveTableUpdates = null;
      }
    };
  }

  void _checkNotClosed() {
    if (_closing != null) {
      throw StateError('This connection pool is closed');
    }
  }

  void _installAbortSignal(RawPoolRequest request, Future<void>? abortSignal) {
    if (abortSignal != null) {
      abortSignal.whenComplete(request.abort);
    }
  }

  /// A broadcast stream of tables affected by write transactions on this
  /// database.
  ///
  /// For each completed transaction that updated at least one table, this will
  /// emit a [List] of affected tables. The stream emits updates asynchronously,
  /// _after_ the source table has been changed.
  ///
  /// This stream will also emit items if the update is made by an independent
  /// isolate or another Dart/Flutter engine in the same process.
  ///
  /// By default, updates are only collected when a [writer] or
  /// [exclusiveAccess] is returned. Emitting in a SQLite commit hook directly
  /// causes race conditions, as the commit might still be ongoing by the time
  /// we emit events here.
  /// For long-running writes that using multiple transactions,
  /// [ConnectionLease.notifyUpdates] can be used to emit updates before a
  /// writer is returned.
  Stream<List<String>> get updatedTables => _updatedTables.stream;

  /// Sends an update notification that will be emitted in [updatedTables].
  ///
  /// Calling this on a pool will also emit [updates] on all other isolates or
  /// Dart/Flutter engines opening a pool at the same path.
  ///
  /// This schedules an update notification immediately, and doesn't wait for
  /// a completed write transaction.
  void dispatchUpdateNotification(List<String> updates) {
    _checkNotClosed();
    _raw.sendCustomUpdateNotification(updates);
  }

  /// Obtains a connection suitable for reads from the connection pool.
  ///
  /// The returned [ConnectionLease] must be returned to the pool via
  /// [ConnectionLease.returnLease] so that it can be given to another writer
  /// later. It has native finalizers attached to it, so the connection would
  /// eventually be returned even if the owning isolate crashes or forgets to
  /// call [ConnectionLease.returnLease]. Explicitly returning the lease is
  /// strongly recommended though.
  ///
  /// If the underlying [PoolConnections] have no underlying
  /// [PoolConnections.readers], read requests may also resolve to the
  /// [PoolConnections.writer] connection. As soon as a reader is added to the
  /// pool (via [addReaders]), new read requests will only resolve to read
  /// connections.
  ///
  /// If an [abortSignal] is given and the future completes before the write
  /// connection became available, the future may complete with an
  /// [PoolAbortException] instead.
  Future<ConnectionLease> reader({Future<void>? abortSignal}) async {
    return _requestReaderOrWriter(false, abortSignal);
  }

  /// Obtains a connection suitable for writes from the connection pool.
  ///
  /// There is only one write connection for the entire pool, so different
  /// isolates or Flutter engines calling this method will not be able to issue
  /// writes concurrently, preventing "database is locked" errors.
  ///
  /// The returned [ConnectionLease] must be returned to the pool via
  /// [ConnectionLease.returnLease] so that it can be given to another writer
  /// later. It has native finalizers attached to it, so the connection would
  /// eventually be returned even if the owning isolate crashes or forgets to
  /// call [ConnectionLease.returnLease]. Explicitly returning the lease is
  /// strongly recommended though.
  ///
  /// If an [abortSignal] is given and the future completes before the write
  /// connection became available, the future may complete with an
  /// [PoolAbortException] instead.
  Future<ConnectionLease> writer({Future<void>? abortSignal}) async {
    return _requestReaderOrWriter(true, abortSignal);
  }

  Future<ConnectionLease> _requestReaderOrWriter(
    bool writer,
    Future<void>? abortSignal,
  ) async {
    _checkNotClosed();
    final (request, future) = _raw.requestSingleConnection(!writer);
    _installAbortSignal(request, abortSignal);

    final connectionPointer = await future;
    final lease = ConnectionLease._(
      PoolConnection.unsafeFromPointer(connectionPointer.connection),
      request,
      writer,
    );
    await lease._rollbackPendingTransaction();
    return lease;
  }

  /// Requests exclusive access to this pool.
  ///
  /// Having exclusive access allows access to all read connections and the
  /// write connection at the same time.
  ///
  /// To unblock after waiters after you're done with exclusive access, call
  /// [ExclusivePoolAccess.close].
  ///
  /// If an [abortSignal] is given and the future completes before the write
  /// connection became available, the future may complete with an
  /// [PoolAbortException] instead.
  Future<ExclusivePoolAccess> exclusiveAccess({
    Future<void>? abortSignal,
  }) async {
    _checkNotClosed();
    final (request, future) = _raw.requestExclusive();
    _installAbortSignal(request, abortSignal);
    await future;

    final (:writer, :readers) = _raw.queryConnections();
    final exclusive = ExclusivePoolAccess._(request, writer, readers);
    await exclusive._rollbackPendingTransactions();
    return exclusive;
  }

  /// Executes the [sql] statement on the write connection.
  Future<ExecuteResult> execute(
    String sql, {
    List<Object?> parameters = const [],
  }) async {
    final connection = await writer();
    try {
      return await connection.execute(sql, parameters);
    } finally {
      connection.returnLease();
    }
  }

  /// Runs a query on a reading connection from the pool.
  Future<ResultSet> readQuery(
    String sql, {
    List<Object?> parameters = const [],
  }) async {
    final connection = await reader();
    try {
      final (rs, _) = await connection.select(sql, parameters);
      return rs;
    } finally {
      connection.returnLease();
    }
  }

  /// Adds additional readers into the pool.
  ///
  /// The additional connections will be used to serve outstanding and
  /// subsequent calls to [reader]. These connections should all point to the
  /// same database file already used by existing pool connections.
  ///
  /// New readers can be added even when an existing read, write or exclusive
  /// lock on the pool is active. An exclusive lock started before new readers
  /// were added will not see added connections in
  /// [ExclusivePoolAccess.readers].
  void addReaders(List<Database> connections) => _raw.addReaders(connections);

  /// Closes this connection pool.
  ///
  /// It is not allowed to call [reader], [writer], [exclusiveAccess] or
  /// [dispatchUpdateNotification] after calling close.
  ///
  /// Requests to the pool that have already been requested continue to be
  /// valid. This method returns a future not completing before all outstanding
  /// requests on this pool have been granted or aborted.
  /// When the [abortOutstandingRequests] parameter is enabled, outstanding
  /// requests are aborted if they have not already been granted.
  ///
  /// Even after the returned future completes, already granted [reader] and
  /// [writer] requests continue to be valid until [ConnectionLease.returnLease]
  /// is called.
  ///
  /// Once all pool instances (across isolates) are closed, the underlying
  /// SQLite connections will be closed as well.
  Future<void> close({bool abortOutstandingRequests = false}) {
    if (abortOutstandingRequests) {
      _raw.abortAllRequests();
    }

    return _closing ??= Future.sync(() async {
      // For backwards compatibility, avoid a microtask delay here if there are
      // no requests to await.
      if (_raw.hasOutstandingRequest) {
        await _raw.waitForIdle();
      }

      _raw.close();
      _receiveTableUpdates?.close();
      _receiveTableUpdates = null;
      _updatedTables.close();
    });
  }

  /// Opens a connection pool, initializing it with connections if this is the
  /// first instance of that pool.
  ///
  /// The [name] uniquely identifies the pool in this process. If two isolates
  /// call [open] with the same name, they'll get access to the same physical
  /// pool.
  ///
  /// [openConnections] should return a [PoolConnections] instance with a writer
  /// and a list of read connections. The exact configuration of those
  /// connections is up to the user, but connections should be configured to use
  /// `WAL` mode and there should be at least one read connection:
  ///
  ///```dart
  /// final pool = SqliteConnectionPool.open(
  ///   name: '/path/to/database.db',
  ///   openConnections: () {
  ///     // Open one write and multiple read connections.
  ///     return PoolConnections(
  ///       openDatabase(true),
  ///       [for (var i = 0; i < 4; i++) openDatabase(false)]
  ///     );
  ///   },
  /// );
  ///
  /// Database openDatabase(bool writer) {
  ///   final db = sqlite3.open('/path/to/database.db');
  ///   db.execute('pragma journal_mode = wal;');
  ///   if (!writer) {
  ///     db.execute('pragma query_only = true');
  ///   }
  /// }
  /// ```
  static SqliteConnectionPool open({
    required String name,
    required PoolConnections Function() openConnections,
  }) {
    return SqliteConnectionPool._(
      name,
      RawSqliteConnectionPool.open(name, openConnections),
    );
  }

  /// Like [open], but calls [openConnections] on a fresh isolate to avoid
  /// blocking the current one in case the setup requires an IO operation.
  static Future<SqliteConnectionPool> openAsync({
    required String name,
    required PoolConnections Function() openConnections,
  }) async {
    final receiveOpenNotification = ReceivePort();
    final firstMessage = receiveOpenNotification.first;
    await Isolate.spawn(_openAsyncEntrypoint, (
      name,
      openConnections,
      receiveOpenNotification.sendPort,
    ));

    final message = await firstMessage;
    // This is either a send port, to which we send a message to close the
    // isolate after we've opened the pool on this side, or an (error, trace)
    // pair on exceptions.
    if (message is! SendPort) {
      final (error, trace) = message as (Object, StackTrace);
      Error.throwWithStackTrace(error, trace);
    }

    final closeIsolate = message;
    final pool = open(
      name: name,
      openConnections: () {
        throw AssertionError(
          'The pool is open in the other isolate, so it should not be '
          're-opened here.',
        );
      },
    );
    closeIsolate.send(null);
    return pool;
  }

  static void _openAsyncEntrypoint(
    (String, PoolConnections Function(), SendPort) options,
  ) async {
    final (name, open, port) = options;
    SqliteConnectionPool pool;
    try {
      pool = SqliteConnectionPool.open(name: name, openConnections: open);
    } catch (e, s) {
      Isolate.exit(port, (e, s));
    }

    // Now that we've opened the pool, inform the other isolate. It can open the
    // same pool and that's guaranteed not to open it.
    final close = ReceivePort();
    port.send(close.sendPort);
    await close.first;

    pool.close();
    close.close();
  }
}

/// A database connection with utilities to safely use it asynchronously.
///
/// This provides asynchronous access to the underlying database. The database
/// can be used directly (through [unsafeAccess]). Typically however, one would
/// use the [select] and [execute] methods to automatically run statements and
/// queries in short-lived background isolates.
base class AsyncConnection {
  final PoolConnection _connection;
  // The native request from which the database has been obtained. Closing this
  // will return the connection to the pool.
  final RawPoolRequest _request;
  final bool _isWriter;

  // Because the database is used across multiple isolates (the current one and
  // the short-lived ones used for computations), we need to guard access to the
  // database with a mutex.
  final Mutex _mutex = Mutex();
  var _closed = false;

  AsyncConnection._(this._connection, this._request, this._isWriter);

  /// If the connection is in a transaction, rolls that transaction back.
  ///
  /// If we receive a connection that hasn't been returned in an idle state
  /// (for instance because the isolate originally using it didn't shut down
  /// cleanly), we want to rollback pending transactions.
  ///
  /// This is meant to be called after a connection has been obtained from the
  /// pool.
  Future<void> _rollbackPendingTransaction() async {
    if (!_connection.database.autocommit) {
      await unsafeAccessOnIsolate((db) => db.database.execute('ROLLBACK'));
    }
  }

  void _checkNotClosed() {
    if (_closed) {
      throw StateError('LeasedDatabase used after callback returned');
    }
  }

  /// Gets unprotected acccess to the [Database] without a mutex.
  ///
  /// Calling this method is unsafe if another call on this [ConnectionLease] is
  /// operating concurrently.
  PoolConnection get unsafeRawConnection => _connection;

  /// Obtains a weak reference to this connection from which another lease can
  /// be constructed, even on anoter isolate.
  ///
  /// The connection returned by [ShareableAsyncConnection.obtainConnection]
  /// may not be used at the same time as this one. Typically, it is used in
  /// child isolates to run statements while the parent isolate waits for
  /// results in an [unsafeAccess] block.
  ShareableAsyncConnection get sharableConnection {
    _checkNotClosed();

    return ShareableAsyncConnection(
      WeakPoolRequest(_request),
      _connection.unsafePointer.address,
      _isWriter,
    );
  }

  /// Calls [computation] as a critical section with the underlying database.
  ///
  /// This method is very easy to misuse, and should be used carefully. In
  /// particular, all of the following can trigger undefined behavior:
  ///
  ///  1. Calling [Database.close].
  ///  2. Calling any method on [Database] after [computation] (or, if it's
  ///     asynchronous, its future) completes.
  Future<T> unsafeAccess<T>(
    FutureOr<T> Function(PoolConnection) computation,
  ) async {
    _checkNotClosed();
    return _mutex.withCriticalSection(() => computation(_connection));
  }

  /// On a short-lived isolate, calls [computation] as a critical section with
  /// the underlying database.
  ///
  /// See [unsafeAccess] for potential issues to be aware of when calling this
  /// method.
  Future<T> unsafeAccessOnIsolate<T>(
    FutureOr<T> Function(PoolConnection) computation,
  ) {
    return unsafeAccess((conn) {
      return Isolate.run(_isolateClosure(computation, sharableConnection));
    });
  }

  static FutureOr<T> Function() _isolateClosure<T>(
    FutureOr<T> Function(PoolConnection) computation,
    ShareableAsyncConnection shared,
  ) {
    return () {
      final connection = shared.obtainConnection();
      if (connection == null) {
        throw StateError('Parent isolate closed first');
      }

      return computation(connection.unsafeRawConnection);
    };
  }

  /// Returns the [Database.autocommit] status for the wrapped database.
  Future<bool> get autocommit {
    // the autocommit call is too cheap to justify a background isolate.
    return unsafeAccess((conn) => conn.database.autocommit);
  }

  /// Runs [sql] with [parameters] and returns results (both the [ResultSet] and
  /// a record of affected rows).
  Future<(ResultSet, ExecuteResult)> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return unsafeAccessOnIsolate((conn) {
      final resultSet = conn.select(sql, parameters);
      return (resultSet, _execResult(conn.database));
    });
  }

  /// Executes [sql] with [parameters] and returns affected rows.
  Future<ExecuteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return unsafeAccessOnIsolate((conn) {
      conn.execute(sql, parameters);

      return _execResult(conn.database);
    });
  }

  void _close() {
    _closed = true;
    // This doesn't call sqlite3_close_v2 because the connection has been opened
    // with borrowed: true. It just prevents using the connection object any
    // further.
    _connection.database.close();
  }

  static ExecuteResult _execResult(Database db) {
    return (
      autoCommit: db.autocommit,
      changes: db.updatedRows,
      lastInsertRowId: db.lastInsertRowId,
    );
  }
}

/// A SQLite database connection that has been leased from a connection pool and
/// must be returned to it with [returnLease].
///
/// If this object is no longer referenced, or if the isolate with exclusive
/// access is closed for any reason, the lease is also automatically returned.

final class ConnectionLease extends AsyncConnection {
  ConnectionLease._(super._connection, super._request, super._isWriter)
    : super._();

  /// Returns this leased connection back to the pool.
  ///
  /// This connection may not be used after calling this method.
  void returnLease() {
    if (!_closed) {
      _close();
      _request.close();
    }
  }

  /// Manual signal to add tables to [SqliteConnectionPool.updatedTables].
  ///
  /// By default, local writes made while a connection was leased from the pool
  /// propagate to [SqliteConnectionPool.updatedTables] when the write
  /// connection is returned. This is a sensible default for most cases, but
  /// long-running writers issuing multiple transactions might want to notify
  /// updates after each transaction without returning the write lease.
  ///
  /// This method emits pending updates when:
  ///
  ///   1. This is a write transaction.
  ///   2. It is not in a transaction ([autocommit] is true).
  ///   3. There are pending writes from an earlier completed transaction that
  ///      haven't made it to [SqliteConnectionPool.updatedTables] yet.
  Future<void> notifyUpdates() {
    return unsafeAccess((_) {
      if (_isWriter && !_closed) {
        _request.notifyUpdates();
      }
    });
  }
}

/// Provides access to all connections of a database pool.
///
/// After obtaining this instance, it must eventually be [close]d to allow other
/// readers and writers to progress.
///
/// If this object is no longer referenced, or if the isolate with exclusive
/// access is closed for any reason, the handle is also automatically returned.
final class ExclusivePoolAccess {
  /// The single write connection of the connection pool.
  final AsyncConnection writer;

  /// All read connections in the pool.
  final List<AsyncConnection> readers;
  final RawPoolRequest _request;

  ExclusivePoolAccess._(
    this._request,
    PoolConnectionRef writer,
    List<PoolConnectionRef> readers,
  ) : writer = AsyncConnection._(
        PoolConnection.unsafeFromPointer(writer.connection),
        _request,
        true,
      ),
      readers = [
        for (final reader in readers)
          AsyncConnection._(
            PoolConnection.unsafeFromPointer(reader.connection),
            _request,
            false,
          ),
      ];

  Future<void> _rollbackPendingTransactions() async {
    await Future.wait([
      writer._rollbackPendingTransaction(),
      for (final reader in readers) reader._rollbackPendingTransaction(),
    ]);
  }

  /// Returns this exclusive access instance, allowing other readers and writers
  /// to use the pool.
  void close() {
    if (writer._closed) {
      return;
    }

    writer._close();
    for (final reader in readers) {
      reader._close();
    }

    _request.close();
  }
}

/// An [AsyncConnection] that can be sent across isolates.
///
/// This is created by [AsyncConnection.unsafeShareableConnection] and forms a
/// _weak_ reference to the underlying connection: If the associated connection
/// lease was returned earlier, it won't be possible to obtain it again.
///
/// Otherwise, [ShareableAsyncConnection.obtainConnection] returns a new strong
/// reference to the same connection. Because this can be called on independent
/// isolates, a typical pattern is to only hand out shareable connections in an
/// [AsyncConnection.unsafeAccess] block.
@pragma('vm:deeply-immutable')
final class ShareableAsyncConnection {
  final WeakPoolRequest _weak;
  final int _connection;
  final bool _isWriter;

  ShareableAsyncConnection(this._weak, this._connection, this._isWriter);

  /// If a strong reference to the original [AsyncConnection] exists anywhere
  /// in the current isolate group, obtains another.
  ///
  /// This function is typically called in child isolates running database
  /// statements. If the parent isolate has exited unexpectedly before this
  /// shared connection was received, it returns null.
  ///
  /// The [ConnectionLease] is only returned into the pool when
  /// [ConnectionLease.returnLease] is called for all strong references. If an
  /// isolate exits while refrencing a connection lease, it is automatically
  /// returned.
  ConnectionLease? obtainConnection() {
    final request = _weak.upgrade();
    if (request == null) return null;

    return ConnectionLease._(
      .unsafeFromPointer(.fromAddress(_connection)),
      request,
      _isWriter,
    );
  }
}
