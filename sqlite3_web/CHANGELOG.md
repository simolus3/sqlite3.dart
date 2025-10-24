## 0.4.0

- Remove `userVersion` and `setUserVersion`. Users should run the pragma statements manually.
- Add `requestLock`, which can be used to make multiple database calls in a locked context.
- Allow aborting requests.
- Add support for a new Web FS (OPFS) access mode based on `readwrite-unsafe`.

## 0.3.2

- Allow workers to send requests to clients. Previously, only the other
  direction was implemented.

## 0.3.1

- Fix hooks not being delivered to all databases.

## 0.3.0

- Allow passing data to worker when opening databases.
- Support `dart2wasm`.
- Serialize `SqliteException`s in workers.
- Serialize parameters and rows instead of using `jsify()` / `dartify()`.

## 0.2.2

- Recover from worker errors at startup.

## 0.2.1

- Add `WebSqlite.deleteDatabase` to delete databases.
- Support opening databases without workers.

## 0.2.0

- Make `FileSystem` implementation functional, add `FileSystem.flush()`.

## 0.1.3

- Support latest version of `package:web`.

## 0.1.2-wip

- Fix preferred databases not being sorted correctly.

## 0.1.1-wip

- Fix remote error after closing databases.

## 0.1.0-wip

- Initial WIP version.
