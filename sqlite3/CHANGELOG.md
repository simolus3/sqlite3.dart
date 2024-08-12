## 2.4.6

- WebAssembly: Call `_initialize` function of sqlite3 module if one is present.
- Support version 1.0.0 of `package:web`.

## 2.4.5

- Fix a bug in the OPFS-locks implementation causing a deadlock when the `xSleep`
  VFS call is issued.
- Fix selecting large integers (being represented as a `BigInt` in Dart)
  not working when compiled with dartdevc.

## 2.4.4

- Add a temporary workaround for [a Dart bug](https://github.com/dart-lang/sdk/issues/56064)
  causing spurious exceptions when databases are closed and a debugger is attached.

## 2.4.3

- Migrate away from legacy web APIs: `dart:html`, `dart:js`, `dart:indexeddb`
  and `package:js` are no longer imported from this package.
- Experimentally support being compiled to WebAssembly. Strong caveats apply,
  please check [#230](https://github.com/simolus3/sqlite3.dart/issues/230)
  before relying on this!

## 2.4.2

- Fix string and blob arguments to prepared statements never being
  deallocated ([#225](https://github.com/simolus3/sqlite3.dart/issues/225)).

## 2.4.1+1

- Allow version `0.7.x` of the `js` package.
- Reduce size of `sqlite3.wasm` bundle by removing symbols not referenced in
  Dart.

## 2.4.0

- Add `isReadOnly` and `isExplain` getters to prepared statements.
- Set `NativeCallable.keepIsolateAlive` to `false` for callables managed by
  this package.

## 2.3.0

- Add the `autocommit` getter on databases wrapping `sqlite3_get_autocommit`.
- Improve the error message in the exception when opening a database fails.

## 2.2.0

- Add `updatedRows` getter to eventually replace `getUpdatedRows()` method.
- Clarify documentation on `lastInsertRowId` and `updatedRows`.
- Allow customizing the amount of pages to lock at a time in `backup`. A larger
  amount will result in better backup performance.
- Use `NativeCallable`s for user-defined functions, collations and update
  streams.

## 2.1.0

- Add `config` getter to `CommonDatabase` to access `sqlite3_db_config`.

## 2.0.0

- __Breaking__: The WASM implementation no longer registers a default virtual
  file system. Instead, `registerVirtualFileSystem` needs to be used to add
  desired file system implementations.
- __Breaking__: Fix a typo, `CommmonSqlite3` is now called `CommonSqlite3`.
- __Breaking__: Introduce class modifiers on classes of this package that aren't
  meant to be extended or implemented by users.
- Add `PreparedStatement.reset()`.
- Add the `CustomStatementParameter` class which can be passed as a statement
  parameter with a custom `sqlite3_bind_*` call.
- Add the `StatementParameters` class and `executeWith`/`selectWith` methods
  on `CommonPreparedStatement`. They can be used to control whether values are
  bound by index or by name. The `selectMap` and `executeMap` methods have
  been deprecated.

## 1.11.2

- Report correct column names for statements that have been re-compiled due to
  schema changes.

## 1.11.1

- Fix user-defined functions returning text not supporting multi-byte utf8
  characters.

## 1.11.0

- Add `WasmSqlite3.loadFromUrl` which uses a streaming `fetch()` request to
  load the sqlite3 WASM binary.
- Add `OpfsFileSystem`, a file system implementation for the WASM library that
  is based on the synchronous File System Access API.
- The WASM version of sqlite3 used by this library is now compiled with `-Oz`
  instead of `-Ofast`.

## 1.10.1

- Fix a regression introduced in 1.10.0 causing crashes when SQL statements
  containing non-ASCII characters are prepared.

## 1.10.0

- Rewrite the implementation to allow more code reuse between `dart:ffi` and
  the WASM-based web implementation.

## 1.9.3

- Provide more information about the source of sqlite exceptions.
- Fix prepared statements without parameters not being reused properly.

## 1.9.2

- Include parameters when throwing an exception in prepared statements.

## 1.9.1

- Change `Row.keys` and `Row.values` to return a list.

## 1.9.0

- Add an API for sqlite3's backup API via `Database.backup()`.
- Add an API to load extensions via `sqlite3.ensureExtensionLoaded`.

## 1.8.0

- Use a `Finalizer` to automatically dispose databases and statements. As
  finalizers in Dart aren't reliable, you should still make sure to call
  `dispose` manually after you're done with a database or a statement.
- Avoid using generative constructors on `@staticInterop` classes.

## 1.7.2

- Optimizations in the wasm-based file system.
- Fix the `mutex` parameter not doing anything in the FFI-based implementation.

## 1.7.1

- Allow binding `BigInt`s to statements and functions. They must still be
  representable as a 64-bit int, but this closes a compatibility gap between
  the web and the native implementations.
- Use ABI-specific integer types internally.

## 1.7.0

- Add support for application-defined window functions. To register a custom
  window function, implement `WindowFunction` and register your function with
  `database.registerAggregateFunction`.
- __Breaking__ (For the experimental `package:sqlite3/wasm.dart` library):
  - The IndexedDB implementation now stores data in 4k blocks instead of full files.
  - Removed `IndexedDbFileSystem.load`. Use `IndexedDbFileSystem.open` instead.
  - An `IndexedDbFileSystem` now stores all files, the concept of a persistence
    root has been removed.
    To access independent databases, use two `IndexedDbFileSystem`s with a different
    database name.

## 1.6.4

- Add `FileSystem.listFiles()` to list all files in a virtual WASM file system.

## 1.6.3

- Support running `sqlite3/wasm.dart` in web workers.

## 1.6.2

- Fix `CURRENT_TIMESTAMP` not working with the WebAssembly backend.

## 1.6.1

- Better support loading sqlite3 on Linux when using `sqlite3_flutter_libs`.

## 1.6.0

- Very experimental web support, based on compiling sqlite3 to web assembly
  with a custom file system implementation.

## 1.5.1

- Fix `checkNoTail` throwing for harmless whitespace or comments following a
  SQL statement.
- Fix a native null-pointer dereference when calling `prepare` with a statement
  exclusively containing whitespace or comments.
- Fix a potential out-of-bounds read when preparing statements.

## 1.5.0

- Add `prepareMultiple` method to prepare multiple statements from one SQL string.
- Add `selectMap` and `executeMap` on `PreparedStatement` to bind SQL parameters by
  their name instead of their index.
- Add support for custom collations with `createCollation`.

## 1.4.0

- Report writes on the database through the `Database.updates` stream
- Internal: Use `ffigen` to generate native bindings

## 1.3.1

- Fix a crash with common iOS and macOS configurations.
  The crash has been introduced in version 1.3.0, which should be avoided.
  Please consider adding `sqlite3: ^1.3.1` to your pubspec to avoid getting the
  broken version

## 1.3.0

- Add `Cursor.tableNames` and `Row.toTableColumnMap()` to obtain tables
  involved in a result set.
  Thanks to [@juancastillo0](https://github.com/juancastillo0)!

## 1.2.0

- Add the `selectCursor` API on `PreparedStatement` to step through a result set row by row.
- Report the causing SQL statement in exceptions
- Use a new Dart API to determine whether symbols are available

## 1.1.2

- Attempt opening sqlite3 from `DynamicLibrary.process()` on macOS

## 1.1.1

- Fix memory leak when preparing statements!
- Don't allow `execute` with arguments when the provided sql string contains
  more than one argument.

## 1.1.0

- Add optional parameters to `execute`.

## 1.0.1

- Don't throw when `PreparedStatement.execute` is used on a statement returning
  rows.

## 1.0.0

- Support version `1.0.0` of `package:ffi`

## 0.1.10-nullsafety.0

- Support version `0.3.0` of `package:ffi`
- Migrate library to support breaking ffi changes in Dart 2.13:
  - Use `Opaque` instead of empty structs
  - Use `Allocator` api

## 0.1.9-nullsafety.2

- Fix loading sqlite3 on iOS

## 0.1.9-nullsafety.1

- Migrate package to null safety

## 0.1.8

- Added the `mutex` parameter to control the serialization mode
  when opening databases.

## 0.1.7

- Expose the `sqlite3_temp_directory` global variable

## 0.1.6

- Expose underlying database and statement handles
- Support opening databases from uris

## 0.1.5

- Use `sqlite3_version` to determine if `sqlite3_prepare_v3` is available
  instead of catching an error.

## 0.1.4

- Use `sqlite3_prepare_v2` if `sqlite3_prepare_v3` is not available

## 0.1.3

- Lower minimum version requirement on `collection` to `^1.14.0`

## 0.1.2

- Enable extended result codes
- Expose raw rows from a `ResultSet`

## 0.1.1

- Expose the `ResultSet` class

## 0.1.0

- Initial version
