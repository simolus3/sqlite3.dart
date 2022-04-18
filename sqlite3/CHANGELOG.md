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
