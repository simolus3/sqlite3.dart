/// @docImport 'pool.dart';
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'abort_exception.dart';
import 'raw.dart';

/// A connection that is part of a connection pool.
///
/// This provides access to the underlying [Database] and the prepared statement
/// cache for the connection.
///
/// Pool connections are owned by the pool. All instances of this class
/// represent _temporary references_ to a pool connection. Further, while pool
/// connections can be sent across isolates, they must never be used
/// concurrently, with the sole exception of [interrupt]. This makes
/// [PoolConnection] an unsafe class to use directly, users should use prefer to
/// use the [AsyncConnection] wrapper instead.
final class PoolConnection {
  /// The leased database connection.
  final Database database;

  final PoolConnectionRef _ref;

  PoolConnection._(this._ref)
    : database = sqlite3.fromPointer(_ref.rawDatabase, borrowed: true);

  /// Wraps a pointer obtained through [unsafePointer].
  ///
  /// To use this safely, see the notes on [unsafePointer].
  factory PoolConnection.unsafeFromPointer(Pointer<void> connection) {
    return PoolConnection._(PoolConnectionRef(connection.cast()));
  }

  /// The underlying pointer representing this pool connection.
  ///
  /// The address of this pointer can safely be sent across isolates, but:
  ///
  ///  1. The connection must never be used concurrently. [interrupt] is the
  ///     only exception to this.
  ///  2. The pointer is only valid until this connection is closed.
  Pointer<void> get unsafePointer {
    return _ref.connection.cast();
  }

  /// Interrupts a statement running on this connection, making later calls to
  /// [select] and [execute] on this lease throw a [PoolAbortException].
  ///
  /// Unlike everything else here, this may be called while another isolate is
  /// using the connection, which is the only way to stop a running statement.
  ///
  /// Don't call this once the lease has been returned, the connection may
  /// belong to someone else by then. Prefer the abortSignal of
  /// [SqliteConnectionPool.reader] and [SqliteConnectionPool.writer].
  void interrupt() => _ref.interrupt();

  /// Whether [interrupt] has been called for the current lease on this
  /// connection.
  bool get isInterrupted => _ref.isInterrupted;

  void _checkNotInterrupted() {
    if (_ref.isInterrupted) {
      throw const PoolAbortException();
    }
  }

  /// Resets [cached] for the next caller, or drops it from the cache when this
  /// lease was interrupted.
  ///
  /// A reset statement is reusable, but it keeps what the partial run recorded,
  /// which a build with `SQLITE_ENABLE_STMT_SCANSTATUS` would keep counting.
  void _resetOrDropCached(Uint8List encoded, PreparedStatement cached) {
    if (_ref.isInterrupted) {
      // Finalizes the statement, so it must not be touched afterwards.
      _ref.removeCachedStatement(encoded);
    } else {
      cached.reset();
    }
  }

  /// Runs [body], reporting a statement that [interrupt] stopped as a
  /// [PoolAbortException].
  ///
  /// We check the flag as well as the result code, so an interrupt coming from
  /// elsewhere stays a [SqliteException].
  T _reportInterruptAsAbort<T>(T Function() body) {
    try {
      return body();
    } on SqliteException catch (e) {
      if (e.resultCode == SqlError.SQLITE_INTERRUPT && _ref.isInterrupted) {
        throw const PoolAbortException();
      }
      rethrow;
    }
  }

  /// Run a query on this connection, using the prepared statement cache if it
  /// has been enabled.
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    _checkNotInterrupted();
    final encoded = utf8.encode(sql);
    final cached = _lookupCached(sql, encoded);

    final ResultSet resultSet;
    if (cached != null) {
      try {
        resultSet = _reportInterruptAsAbort(() => cached.select(parameters));
      } finally {
        _resetOrDropCached(encoded, cached);
      }
    } else {
      final stmt = database.prepare(sql, checkNoTail: true);
      try {
        // Checked again after compiling, since SQLite discards an interrupt
        // arriving before a statement's first sqlite3_step.
        _checkNotInterrupted();
        resultSet = _reportInterruptAsAbort(() => stmt.select(parameters));
      } finally {
        stmt.reset();
        // An interrupted statement is the tail of a cancelled query, so it is
        // closed instead of being kept for the next caller.
        if (_ref.isInterrupted || !_storeCached(encoded, stmt)) {
          stmt.close();
        }
      }
    }

    return resultSet;
  }

  /// Executes the given [sql] statement with the [parameters].
  ///
  /// If parameters are empty, [sql] is allowed to contain more than one
  /// statement. Otherwise, this relies on prepared statements which might be
  /// cached depending on how the pool is configured.
  void execute(String sql, [List<Object?> parameters = const []]) {
    _checkNotInterrupted();
    final encoded = utf8.encode(sql);

    if (_lookupCached(sql, encoded) case final cached?) {
      try {
        _reportInterruptAsAbort(() => cached.execute(parameters));
      } finally {
        _resetOrDropCached(encoded, cached);
      }
    } else if (parameters.isNotEmpty) {
      final stmt = database.prepare(sql, checkNoTail: true);
      try {
        // See the note in select.
        _checkNotInterrupted();
        _reportInterruptAsAbort(() => stmt.execute(parameters));
      } finally {
        stmt.reset();
        // See the note in select.
        if (_ref.isInterrupted || !_storeCached(encoded, stmt)) {
          stmt.close();
        }
      }
    } else {
      // The sql text is allowed to contain multiple statements, so we can't
      // cache them.
      _reportInterruptAsAbort(() => database.execute(sql));
    }
  }

  PreparedStatement? lookupCachedStatement(String sql) {
    return _lookupCached(sql, utf8.encode(sql));
  }

  PreparedStatement? _lookupCached(String sql, Uint8List encoded) {
    final ptr = _ref.lookupCachedStatement(encoded);
    if (ptr.address == 0) return null;

    return database.statementFromPointer(
      statement: ptr,
      sql: sql,
      borrowed: true,
    );
  }

  /// A call to this method invalidates all prior [lookupCachedStatement] return
  /// values, as the underlying statement could have been evicted from this
  /// call.
  bool storeCachedStatement(String sql, PreparedStatement stmt) {
    return _storeCached(utf8.encode(sql), stmt);
  }

  bool _storeCached(Uint8List encoded, PreparedStatement stmt) {
    // Avoid caching EXPLAIN statements, as their information can become
    // outdated with schema changes.
    if (stmt.isExplain) return false;

    final didInsert = _ref.putCachedStatement(encoded, stmt.handle.cast());
    if (didInsert) {
      // Detach Dart finalizer to move ownership into the pool.
      stmt.leak();
      return true;
    }

    return false;
  }
}
