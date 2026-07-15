# SQLite for Dart

Provides Dart bindings to [SQLite](https://www.sqlite.org/index.html), both on native platforms
and the web.

## Installation

Because this library uses [hooks](https://dart.dev/tools/hooks), it bundles SQLite with
your application and doesn't require any external dependencies or build configuration.
To use it, depend on it:

```shell
dart pub add sqlite3
```

To use this library on the web, additional setup is necessary:

- You need a copy of SQLite as a WebAssembly module, available from the
  [GitHub releases](https://github.com/simolus3/sqlite3.dart/releases) of this package.
  Note that, for this package, __sqlite3 has to be compiled in a special way__.
  Existing WebAssembly files from e.g. sql.js will not work with `package:sqlite3/wasm.dart`.
  You can also see [this directory](https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3_wasm_build)
  for the build files to compile this yourself.
- Because websites can't access the host's file system, this also needs a
  virtual file system implementation. This package provides `InMemoryFileSystem`,
  `IndexedDbFileSystem` and OPFS-based file system implementations.

> [!TIP]
> This package provides direct and synchronous access to SQLite. For most apps, running SQLite in a background
> isolate or web worker is a much better option, and there are packages to help you with that:
> [`sqlite_async`](https://pub.dev/packages/sqlite_async) and sqflite (through [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) and [sqflite_common_ffi_web](https://pub.dev/packages/sqflite_common_ffi_web))
> provide common interfaces and platform-specific asynchronous implementations.
>
> Additionally, projects like [drift](https://drift.simonbinder.eu) and [typed_sql](https://pub.dev/packages/typed_sql)
> provide type-safety for SQL queries.

## Opening databases

While using SQLite on native platforms is straightforward, using it on the web requires additional setup to
load the WebAssembly module.

### Native

On native platforms, use the `sqlite3` constant to open databases:

```dart
import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.open('test.db');
  db
    ..execute(
      'CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY, name TEXT) STRICT',
    )
    ..execute('INSERT INTO users (name) VALUES (?)', ['SQLite user']);

  print(db.select('SELECT * FROM users'));
}
```

For a more complete example on how to use this library, see the [example](https://pub.dev/packages/sqlite3/example).

### Web

On the web, download a `sqlite3.wasm` as described in the [installation steps](#installation).
Then, load and instantiate a WebAssembly module to use SQLite:

```dart
import 'package:sqlite3/wasm.dart';

Future<WasmSqlite3> loadSqlite() async {
  final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3.wasm');
  final fileSystem = await IndexedDbFileSystem.open(dbName: 'my_app');
  sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);
  return sqlite;
}

void main() async {
  final sqlite3 = await loadSqlite();
  final db = sqlite3.open('test.db');
  db
    ..execute(
      'CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY, name TEXT) STRICT',
    )
    ..execute('INSERT INTO users (name) VALUES (?)', ['SQLite user']);

  print(db.select('SELECT * FROM users'));
  db.close();
}
```

An example for such web folder is in `example/web/` of this repo.
To view the example, copy a compiled `sqlite3.wasm` file to `web/sqlite3.wasm` in this directory.
Then, run `dart run build_runner serve example:8080` and visit `http://localhost:8080/web/` in a browser.

Another example in `../examples/multiplatform/` uses common interface to `sqlite3` on web and native platforms.
To run this example, merge its files into a Flutter app.

### Sharing database code

This package provides distinct imports for native (`package:sqlite3/sqlite3.dart`) and web (`pacakge:sqlite3/wasm.dart`)
platforms.
When writing platform-independent code, import `package:sqlite3/common.dart` to use shared interfaces that work on all
platforms.

The common import provides full support for databases (`CommonDatabase`) and prepared statements (`CommonPreparedStatement`).
`CommonSqlite3` is implemented by both `WasmSqlite3` and the `sqlite3` constant on native platforms.

## Supported datatypes

When binding parameters to queries, the supported types are `ìnt`,
`double`, `String`, `List<int>` (for `BLOB`) and `null`.
Consider using a `Uint8List` when binding binary values for better performance.
Result sets will use the same set of types (and consistently use `Uint8List` for blobs).

On the web (when compiled with `dart2js`), `BigInt` is supported as well to represent 64bit integers.
Support for this can be disabled with `-Dsqlite3.dartbigints=false`.

## Supported platforms

This library provides prebuilt versions of SQLite for the following platforms:

- __Android__: `armv7a`, `aarch64`, `x86`, `x64`.
- __iOS__: `arm64` (devices), `arm64` (simulator), `x64` (simulator).
- __macOS__: `arm64`, `x64`.
- __Linux__: `armv7`, `aarch64`, `x64`, `x86`, `riscv64gc`.
- __Windows__: `aarch64`, `x64`, `x86`.
- __Web__: Tested on Firefox, Chrome and Safari. When using `dart2wasm`, consider using a web worker from helper
  packages like `drift` or `sqlite_async` for better performance.

On all native platforms, you can also use SQLite3MultipleCiphers or SQLCipher instead of SQLite to encrypt
databases. The [hook options page](./doc/hook.md) describe this setup.

Support for encrypted databases is also available on the web using the `sqlite3mc.wasm` asset uploaded to
[releases](https://github.com/simolus3/sqlite3.dart/releases):

```dart
final sqlite3 = await WasmSqlite3.loadFromUrlString('sqlite3mc.wasm');
sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);

final database = sqlite3.open('/database')
  ..execute("pragma key = 'test';"); // TODO: Replace key
```
