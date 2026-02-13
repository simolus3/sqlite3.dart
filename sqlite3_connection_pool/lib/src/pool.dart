import 'package:sqlite3/sqlite3.dart';

import 'raw.dart';

final class SqliteConnectionPool {
  final RawSqliteConnectionPool _raw;

  SqliteConnectionPool._(this._raw);

  static SqliteConnectionPool open({
    required String name,
    required PoolConnections Function() openConnections,
  }) {
    return SqliteConnectionPool._(
      RawSqliteConnectionPool.open(name, openConnections),
    );
  }
}

/// A SQLite database connection that has been leased from a connection pool and
/// must be returned.
final class ConnectionLease {
  /// The leased database connection.
  final Database database;

  ConnectionLease._(this.database);

  void returnLease() {}
}
