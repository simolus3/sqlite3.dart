import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:meta/meta.dart';

import '../../result_set.dart';
import '../api.dart';
import '../implementation.dart';
import 'mutex.dart';

final class ConnectionPool {
  final Database _writer;
  final Mutex _writerMutex = Mutex();

  var _writerClosed = false;
  var _readersClosed = false;
  final MultiSemaphore<Database> _readers;

  @experimental
  ConnectionPool(this._writer, Iterable<Database> readers)
      : _readers = MultiSemaphore(readers);

  Future<T> withWriter<T>(
      FutureOr<T> Function(LeasedDatabase db) callback) async {
    return _writerMutex
        .withCriticalSection(() => callback(LeasedDatabase._(_writer)));
  }

  Future<T> withReader<T>(
      FutureOr<T> Function(LeasedDatabase db) callback) async {
    return _readers.withPermits(
        1, (dbs) => callback(LeasedDatabase._(dbs.single)));
  }

  Future<void> close() {
    Future<void> closeWriter() {
      return withWriter((db) {
        if (!_writerClosed) {
          _writerClosed = true;
          db._database.dispose();
        }
      });
    }

    Future<void> closeReaders() {
      return _readers.withPermits(_readers.poolSize, (dbs) {
        if (!_readersClosed) {
          _readersClosed = true;
          for (final reader in dbs) {
            reader.dispose();
          }
        }
      });
    }

    return Future.wait([
      if (!_readersClosed) closeReaders(),
      if (!_writerClosed) closeWriter(),
    ]);
  }
}

typedef ExecuteResult = ({
  bool autoCommit,
  int changes,
  int lastInsertRowId,
});

final class LeasedDatabase {
  final Database _database;
  // Because the database is used across multiple isolates (the current one and
  // the short-lived ones used for computations), we need to guard access to the
  // database with a mutex.
  final Mutex _mutex = Mutex();

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
    return _computeOnIsolate(_execResult);
  }

  static ExecuteResult _execResult(Database db) {
    return (
      autoCommit: db.autocommit,
      changes: db.updatedRows,
      lastInsertRowId: db.lastInsertRowId,
    );
  }
}
