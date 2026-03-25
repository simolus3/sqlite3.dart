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
