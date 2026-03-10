/// @docImport 'pool.dart';
library;

import 'package:meta/meta.dart';
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

@internal
PoolConnection poolConnectionFromPointer(PoolConnectionRef ref) {
  return PoolConnection._(ref);
}

@internal
PoolConnectionRef poolConnectionToPointer(PoolConnection conn) {
  return conn._ref;
}
