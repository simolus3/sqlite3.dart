/// @docImport 'pool.dart';
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

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
    final encoded = utf8.encode(sql);
    final cached = _lookupCached(sql, encoded);

    final ResultSet resultSet;
    if (cached != null) {
      resultSet = cached.select(parameters);
      cached.reset();
    } else {
      final stmt = database.prepare(sql, checkNoTail: true);
      resultSet = stmt.select(parameters);
      stmt.reset();
      if (!_storeCached(encoded, stmt)) {
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
    final encoded = utf8.encode(sql);

    if (_lookupCached(sql, encoded) case final cached?) {
      cached
        ..execute(parameters)
        ..reset();
    } else if (parameters.isNotEmpty) {
      final stmt = database.prepare(sql, checkNoTail: true);
      stmt
        ..execute(parameters)
        ..reset();
      if (!_storeCached(encoded, stmt)) {
        stmt.close();
      }
    } else {
      // The sql text is allowed to contain multiple statements, so we can't
      // cache them.
      database.execute(sql);
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
