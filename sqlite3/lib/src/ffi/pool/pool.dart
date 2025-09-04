import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:meta/meta.dart';

import '../../result_set.dart';
import '../api.dart';
import '../implementation.dart';
import 'mutex.dart';

/// An asynchronous connection pool backed by a fixed amount of connections
/// accessed through short-lived isolates using [Isolate.run].
///
/// This connection pool implementation is only available when using SQLite with
/// native assets.
@experimental
final class ConnectionPool {
  final Database _writer;
  final Mutex _writerMutex = Mutex();
  final MultiSemaphore<Database> _readers;

  var _writerClosed = false;
  var _readersClosed = false;

  @experimental
  ConnectionPool(this._writer, Iterable<Database> readers)
      : _readers = MultiSemaphore(readers);

  void _checkNotClosed() {
    if (_writerClosed || _readersClosed) {
      throw StateError('ConnectionPool is closed');
    }
  }

  Future<T> withWriter<T>(
      FutureOr<T> Function(LeasedDatabase db) callback) async {
    _checkNotClosed();
    return _writerMutex.withCriticalSection(
        () => LeasedDatabase._wrapWithLease(_writer, callback));
  }

  Future<T> withReader<T>(
      FutureOr<T> Function(LeasedDatabase db) callback) async {
    _checkNotClosed();
    return _readers.withPermits(
        1, (dbs) => LeasedDatabase._wrapWithLease(dbs.single, callback));
  }

  Future<T> withAllConnections<T>(
      FutureOr<T> Function(List<LeasedDatabase> readers, LeasedDatabase writer)
          callback) async {
    _checkNotClosed();
    return withWriter((writer) async {
      return _readers.withPermits(
        _readers.poolSize,
        (readers) {
          final wrappedReaders = [
            for (final reader in readers) LeasedDatabase._(reader)
          ];

          return Future.sync(() => callback(wrappedReaders, writer))
              .whenComplete(() {
            for (final reader in wrappedReaders) {
              reader._closed = true;
            }
          });
        },
      );
    });
  }

  /// Executes the [sql] statement on the write connection.
  Future<ExecuteResult> execute(String sql,
      [List<Object?> parameters = const []]) {
    return withWriter((conn) => conn.execute(sql, parameters));
  }

  /// Runs a query on a reading connection from the pool.
  Future<ResultSet> readQuery(String sql,
      [List<Object?> parameters = const []]) async {
    final (rs, _) = await withReader((conn) => conn.select(sql, parameters));
    return rs;
  }

  /// Closes the pool and its connections.
  ///
  /// The other methods must not be called after calling [close]. However, it's
  /// legal to call the other methods and use the connection and call [close]
  /// concurrently. In that case, [close] will wait for the [LeasedDatabase] to
  /// be returned.
  Future<void> close() {
    Future<void> closeWriter() {
      _writerClosed = true;
      return _writerMutex.withCriticalSection(_writer.dispose);
    }

    Future<void> closeReaders() {
      _readersClosed = true;

      return _readers.withPermits(_readers.poolSize, (dbs) {
        for (final reader in dbs) {
          reader.dispose();
        }
      });
    }

    return Future.wait([
      if (!_readersClosed) closeReaders(),
      if (!_writerClosed) closeWriter(),
    ]);
  }
}

/// The result of calling [LeasedDatabase.execute]. This provides access to the
/// `autocommit` state (indicating whether the database is in a transaction) as
/// well as the changes and last insert rowid.
typedef ExecuteResult = ({
  bool autoCommit,
  int changes,
  int lastInsertRowId,
});

/// A temporary view on a [Database] that is part of a [ConnectionPool].
///
/// This provides asynchronous access to the underlying database. The database
/// can be used directly (through [unsafeAccess]). Typically however, one would
/// use the [select] and [execute] methods to automatically run statements and
/// queries in a short-lived background isolate.
final class LeasedDatabase {
  final Database _database;
  // Because the database is used across multiple isolates (the current one and
  // the short-lived ones used for computations), we need to guard access to the
  // database with a mutex.
  final Mutex _mutex = Mutex();
  var _closed = false;

  LeasedDatabase._(this._database);

  /// Calls [computation] as a critical section with the underlying database.
  ///
  /// This method is very easy to misuse, and should be used carefully. In
  /// particular, all of the following trigger undefined behavior:
  ///
  ///  1. Calling [Database.dispose].
  ///  2. Calling any method on [Database] after [computation] (or, if it's
  ///     asynchronous, its future) completes.
  Future<T> unsafeAccess<T>(FutureOr<T> Function(Database) computation) async {
    if (_closed) {
      throw StateError('LeasedDatabase used after callback returned');
    }

    return _mutex.withCriticalSection(() => computation(_database));
  }

  Future<T> _computeOnIsolate<T>(
      FutureOr<T> Function(Database) computation) async {
    return unsafeAccess((db) {
      final address = db.handle.address;
      return Isolate.run(() {
        final database =
            FfiSqlite3.nativeAssets().fromPointer(Pointer.fromAddress(address));
        return computation(database);
      });
    });
  }

  /// Returns the [Database.autocommit] status for the wrapped database.
  Future<bool> get autocommit {
    // the autocommit call is too cheap to require a background isolate.
    return unsafeAccess((db) => db.autocommit);
  }

  /// Runs [sql] with [parameters] and returns results (both the [ResultSet] and
  /// a record of affected rows).
  Future<(ResultSet, ExecuteResult)> select(String sql,
      [List<Object?> parameters = const []]) {
    return _computeOnIsolate((db) {
      final resultSet = db.select(sql, parameters);
      return (resultSet, _execResult(db));
    });
  }

  /// Executes [sql] with [parameters] and returns affected rows.
  Future<ExecuteResult> execute(String sql,
      [List<Object?> parameters = const []]) {
    return _computeOnIsolate((db) {
      db.execute(sql, parameters);
      return _execResult(db);
    });
  }

  static ExecuteResult _execResult(Database db) {
    return (
      autoCommit: db.autocommit,
      changes: db.updatedRows,
      lastInsertRowId: db.lastInsertRowId,
    );
  }

  static Future<T> _wrapWithLease<T>(
      Database db, FutureOr<T> Function(LeasedDatabase) callback) {
    final lease = LeasedDatabase._(db);
    return Future.sync(() => callback(lease))
        .whenComplete(() => lease._closed = true);
  }
}
