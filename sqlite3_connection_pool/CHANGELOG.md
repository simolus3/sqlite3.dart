## 0.2.7

- Avoid caching `EXPLAIN` statements.

## 0.2.6

- Allow disabling builtin update hooks.
- Add `SqliteConnectionPool.dispatchUpdateNotification` to dispatch custom update notifications.

## 0.2.5

- Support `package:hooks` versions `2.x`.

## 0.2.4

- Fix `SqliteConnectionPool.updatedTables` emitting updates before a transaction has completed.

## 0.2.3

- Close read connections before write connection to clean up `-wal` and `-shm` files.
- Add `select` and `execute` helpers to `PoolConnection`.
- Add `PoolConnection.unsafePointer` and `PoolConnection.unsafeFromPointer`.

## 0.2.2

- Rollback transactions potentially left from killed isolates previously using a connection.

## 0.2.1

- Export the `PoolConnection` class.
- Fix errors in `openAsync` being unhandled.

## 0.2.0+1

- Add `SqliteConnectionPool.openAsync` to open pools asynchronously.
- Add `SqliteConnectionPool.updatedTables` to listen for table updates.
- Add `PoolConnections.preparedStatementCacheSize`. When set to a positive value, `execute` and `select` will cache used prepared statements.

## 0.1.1

- Migrate to automated publishing.

## 0.1.0

- Initial version.
