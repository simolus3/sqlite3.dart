import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:meta/meta.dart';

import '../../result_set.dart';
import '../api.dart';
import '../implementation.dart';
import 'mutex.dart';
import 'pool.dart';

/// The result of calling [LeasedDatabase.execute]. This provides access to the
/// `autocommit` state (indicating whether the database is in a transaction) as
/// well as the changes and last insert rowid.
///
/// {@category native}
typedef ExecuteResult = ({bool autoCommit, int changes, int lastInsertRowId});

/// A temporary view on a [Database] that is part of a [ConnectionPool].
///
/// This provides asynchronous access to the underlying database. The database
/// can be used directly (through [unsafeAccess]). Typically however, one would
/// use the [select] and [execute] methods to automatically run statements and
/// queries in short-lived background isolates.
///
/// {@category native}
final class LeasedDatabase {
  final Database _database;
  // Because the database is used across multiple isolates (the current one and
  // the short-lived ones used for computations), we need to guard access to the
  // database with a mutex.
  final Mutex _mutex = Mutex();
  var _closed = false;

  LeasedDatabase._(this._database);

  /// Gets unprotected acccess to the [Database] without a mutex.
  ///
  /// Calling this method is unsafe if another call on this [LeasedDatabase] is
  /// operating concurrently.
  Database get unsafeRawDatabase => _database;

  /// Calls [computation] as a critical section with the underlying database.
  ///
  /// This method is very easy to misuse, and should be used carefully. In
  /// particular, all of the following can trigger undefined behavior:
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

  /// On a short-lived isolate, calls [computation] as a critical section with
  /// the underlying database.
  ///
  /// See [unsafeAccess] for potential issues to be aware of when calling this
  /// method.
  Future<T> unsafeAccessOnIsolate<T>(
    FutureOr<T> Function(Database) computation,
  ) {
    return unsafeAccess((db) {
      final address = db.handle.address;
      return Isolate.run(() {
        final database = pointerToDatabase(address);
        return computation(database);
      });
    });
  }

  /// Returns the [Database.autocommit] status for the wrapped database.
  Future<bool> get autocommit {
    // the autocommit call is too cheap to justify a background isolate.
    return unsafeAccess((db) => db.autocommit);
  }

  /// Runs [sql] with [parameters] and returns results (both the [ResultSet] and
  /// a record of affected rows).
  Future<(ResultSet, ExecuteResult)> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return unsafeAccessOnIsolate((db) {
      final resultSet = db.select(sql, parameters);
      return (resultSet, _execResult(db));
    });
  }

  /// Executes [sql] with [parameters] and returns affected rows.
  Future<ExecuteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return unsafeAccessOnIsolate((db) {
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
}

@internal
Future<T> wrapWithLease<T>(
  Database db,
  FutureOr<T> Function(LeasedDatabase) callback,
) {
  final lease = LeasedDatabase._(db);
  return Future.sync(
    () => callback(lease),
  ).whenComplete(() => lease._closed = true);
}

@internal
Future<T> wrapWithLeases<T>(
  List<Database> dbs,
  FutureOr<T> Function(List<LeasedDatabase>) callback,
) {
  final wrapped = [for (final db in dbs) LeasedDatabase._(db)];

  return Future.sync(() => callback(wrapped)).whenComplete(() {
    for (final db in wrapped) {
      db._closed = true;
    }
  });
}

Database pointerToDatabase(int address) {
  return const FfiSqlite3().fromPointer(Pointer.fromAddress(address));
}
