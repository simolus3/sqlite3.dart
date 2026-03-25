/// @docImport 'pool.dart';
library;

import 'dart:ffi';

import 'package:sqlite3/sqlite3.dart';

import 'raw.dart';

/// A connection that is part of a connection pool.
///
/// This provides access to the underlying [Database] and the prepared statement
/// cache for the connection.
///
/// Pool connections are owned by the pool. All instances of this class
/// represent _temporary references_ to a pool connection. Further, while pool
/// connections can be sent across isolates, they must never be used
/// concurrently. This makes [PoolConnection] an unsafe class to use directly,
/// users should use prefer to use the [AsyncConnection] wrapper instead.
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
  ///  1. The connection must never be used concurrently.
  ///  2. The pointer is only valid until this connection is closed.
  Pointer<void> get unsafePointer {
    return _ref.connection.cast();
  }

  /// Run a query on this connection, using the prepared statement cache if it
  /// has been enabled.
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    final cached = lookupCachedStatement(sql);

    final ResultSet resultSet;
    if (cached != null) {
      resultSet = cached.select(parameters);
      cached.reset();
    } else {
      final stmt = database.prepare(sql, checkNoTail: true);
      resultSet = stmt.select(parameters);
      stmt.reset();
      if (!storeCachedStatement(sql, stmt)) {
        stmt.close();
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
    if (lookupCachedStatement(sql) case final cached?) {
      cached
        ..execute(parameters)
        ..reset();
    } else if (parameters.isNotEmpty) {
      final stmt = database.prepare(sql, checkNoTail: true);
      stmt
        ..execute(parameters)
        ..reset();
      if (!storeCachedStatement(sql, stmt)) {
        stmt.close();
      }
    } else {
      // The sql text is allowed to contain multiple statements, so we can't
      // cache them.
      database.execute(sql);
    }
  }

  PreparedStatement? lookupCachedStatement(String sql) {
    final ptr = _ref.lookupCachedStatement(sql);
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
    final didInsert = _ref.putCachedStatement(sql, stmt.handle.cast());
    if (didInsert) {
      // Detach Dart finalizer to move ownership into the pool.
      stmt.leak();
      return true;
    }

    return false;
  }
}
