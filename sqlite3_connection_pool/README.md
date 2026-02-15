# sqlite3_connection_pool

A high-performance connection pool for SQLite on native platforms.

## Background

SQLite is a synchronous database engine, and this is reflected by `package:sqlite3` having
synchronous methods as well.
To avoid doing IO on your UI isolate, one typically wraps the `sqlite3` package in a system
that transparently runs queries on a background isolate (drift, sqlite_async and sqflite_common_ffi
all do this).

Having an isolate act as a "server" for SQLite queries works, but doesn't come without issues:

1. The communication scheme between isolates is complex to write.
2. To avoid "database is locked" errors, database access _must_ be coordinated through that isolate.
   For use-cases like background tasks, getting two isolates in the same process to talk to each
   other can be complicated.
3. Copying results over isolates can be expensive for large result sets.

This package explores a different approach that doesn't have those limitations.
Instead of managing a connection pool in Dart, it is maintained by a small Rust library.
The library keeps a global map of active connection pools, so pools can be used even across
Flutter engines or background tasks.

While the pool is asynchronous, it hands out `Database` instances from the `sqlite3` package that
can be used synchronously. If you're using databases on existing background isolates where synchronous
access is okay, this is _much_ cheaper.

Databases can also be used asynchronously. To implement that, the library spawns a short-lived isolate
for each call that runs the query. In modern Dart versions, spawning isolates is very cheap.
Additionally, because each isolate only runs one query, we can "move" result sets across isolates
instead of having to copy!

## Overview

To open a connection pool, call `SqliteConnectionPool.open`. That method takes a name, which should
typically be the path of the database, and a callback to initialize connections:

```dart
final pool = SqliteConnectionPool.open(
  name: '/path/to/database.db',
  openConnections: () {
    // Open one write and multiple read connections.
    return PoolConnections(
      openDatabase(true),
      [for (var i = 0; i < 4; i++) openDatabase(false)]
    );
  },
);

Database openDatabase(bool writer) {
  final db = sqlite3.open('/path/to/database.db');
  db.execute('pragma journal_mode = wal;');
  if (!writer) {
    db.execute('pragma query_only = true');
  }
}
```

Note that opening pools is synchronized: If two isolates race to create the same pool, `openConnections`
will only be called on one of them.

After you have access to a pool, you can:

- Run statements on the write connection: `await pool.execute('CREATE TABLE foo (bar TEXT);')`.
- Run queries on a read connection: `await pool.readQuery('SELECT * FROM foo')`.
- Obtain a read or write connection for multiple queries with `await pool.reader()` or `await pool.writer()`.
 Connections obtained this way must be returned into the pool with `returnLease()`.
- Inspect all connections at once with `await pool.exclusiveAccess()`.

You can explicitly close pools with `close()`, the underlying connections will be closed once all pools
with the shared name have been closed.
