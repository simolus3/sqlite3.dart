import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';

import '../../result_set.dart';
import '../api.dart';
import 'leased_database.dart';
import 'mutex.dart';

/// An asynchronous connection pool backed by a fixed amount of connections
/// accessed through short-lived isolates using [Isolate.run].
///
/// The pool is backed by a single "write" connection and multiple "read"
/// connections. The pool does not enforce that read connections are only used
/// for reads though, nor does it set the connections up.
/// Typically, one would use connections with `pragma journal_mode = wal` with
/// a [ConnectionPool], since the single-writer and many-readers pattern matches
/// what WAL supports natively.
///
/// {@category native}
abstract base class ConnectionPool {
  ConnectionPool._();

  /// Creates a connection pool from a designated [writer] and multiple
  /// [readers].
  ///
  /// These connections should point to a WAL database, the connection pool does
  /// not configure them in any way.
  factory ConnectionPool(Database writer, Iterable<Database> readers) =
      _LocalPool;

  /// Runs [callback] with the writing connection from the pool.
  ///
  /// If [abort] is set and completes before [callback] is called, the future
  /// completes by throwing an [PoolAbortException] without ever calling
  /// [callback]. As soon as [callback] is called, the effects of [abort] are
  /// ignored.
  Future<T> withWriter<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    Future<void>? abort,
  });

  /// Runs [callback] with a reader connection from the pool.
  ///
  /// If [abort] is set and completes before [callback] is called, the future
  /// completes by throwing an [PoolAbortException] without ever calling
  /// [callback]. As soon as [callback] is called, the effects of [abort] are
  /// ignored.
  Future<T> withReader<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    Future<void>? abort,
  });

  /// First obtains a write lock, then locks all readers at once and calls
  /// [callback] with all connections.
  Future<T> withAllConnections<T>(
    FutureOr<T> Function(List<LeasedDatabase> readers, LeasedDatabase writer)
    callback,
  );

  /// Executes the [sql] statement on the write connection.
  Future<ExecuteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return withWriter((conn) => conn.execute(sql, parameters));
  }

  /// Runs a query on a reading connection from the pool.
  Future<ResultSet> readQuery(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final (rs, _) = await withReader((conn) => conn.select(sql, parameters));
    return rs;
  }

  /// Closes the pool and its connections.
  ///
  /// The other methods must not be called after calling [close]. However, it's
  /// legal to call the other methods and use the connection and call [close]
  /// concurrently. In that case, [close] will wait for the [LeasedDatabase] to
  /// be returned.
  Future<void> close();
}

// Hack to only allow implementing ConnectionPool internally (ConnectionPool is
// a base class with a private constructor, and this subclass is not exported).
@internal
abstract base class PoolImplementation extends ConnectionPool {
  PoolImplementation() : super._();
}

/// The default pool implementation, using database connections managed on the
/// current isolate.
///
/// A temporary reference to those connections is used after obtaining locks,
/// and only those references are sent to background isolates to run queries.
@experimental
final class _LocalPool extends PoolImplementation {
  final Database _writer;
  final Mutex _writerMutex = Mutex();
  final MultiSemaphore<Database> _readers;

  var _writerClosed = false;
  var _readersClosed = false;

  _LocalPool(this._writer, Iterable<Database> readers)
    : _readers = MultiSemaphore(readers);

  void _checkNotClosed() {
    if (_writerClosed || _readersClosed) {
      throw StateError('ConnectionPool is closed');
    }
  }

  @override
  Future<T> withWriter<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    Future<void>? abort,
  }) async {
    _checkNotClosed();
    return _writerMutex.withCriticalSection(
      () => wrapWithLease(_writer, callback),
      abort: abort,
    );
  }

  @override
  Future<T> withReader<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    Future<void>? abort,
  }) async {
    _checkNotClosed();
    return _readers.withPermits(
      1,
      (dbs) => wrapWithLease(dbs.single, callback),
      abort: abort,
    );
  }

  @override
  Future<T> withAllConnections<T>(
    FutureOr<T> Function(List<LeasedDatabase> readers, LeasedDatabase writer)
    callback,
  ) async {
    _checkNotClosed();
    return withWriter((writer) async {
      return _readers.withPermits(_readers.poolSize, (readers) {
        return wrapWithLeases(readers, (readers) => callback(readers, writer));
      });
    });
  }

  @override
  Future<void> close() {
    Future<void> closeWriter() {
      _writerClosed = true;
      return _writerMutex.withCriticalSection(_writer.close);
    }

    Future<void> closeReaders() {
      _readersClosed = true;

      return _readers.withPermits(_readers.poolSize, (dbs) {
        for (final reader in dbs) {
          reader.close();
        }
      });
    }

    return Future.wait([
      if (!_readersClosed) closeReaders(),
      if (!_writerClosed) closeWriter(),
    ]);
  }
}

/// An exception signalling that a request on a pool has been aborted.
@pragma('vm:deeply-immutable')
final class PoolAbortException implements Exception {
  const PoolAbortException();

  @override
  String toString() {
    return 'PoolAbortException: A request on a pool was aborted because the '
        'passed abort future completed';
  }
}
