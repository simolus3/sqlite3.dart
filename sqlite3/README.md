# sqlite3

Provides Dart bindings to [SQLite](https://www.sqlite.org/index.html) via `dart:ffi`.

> [!TIP]
> Version 3 of `package:sqlite3` is a major update relying on build hooks and
> code assets to load SQLite. Version 2 of `package:sqlite` will continue to be
> supported and updated until early 2026.
> See [these notes](../UPGRADING_TO_V3.md) for details on how to upgrade.

## Using this library

Because this library uses [hooks](https://dart.dev/tools/hooks), it bundles SQLite with
your application and doesn't require any external dependencies or build configuration.
To use it, depend on it:

```shell
dart pub add sqlite3
```

For native platforms, the basic sketch for using this library is to:

1. Import `package:sqlite3/sqlite3.dart`.
2. Use `sqlite3.open()` to open a database file, or `sqlite3.openInMemory()` to
   open a temporary in-memory database.
3. Use `Database.execute` or `Database.prepare` to execute statements directly
   or by preparing them first.
4. Consider closing statements or databases explicitly with `close()` once you're
   done with them. `package:sqlite3` uses native finalizers to do that automatically
   too, though.

For a more complete example on how to use this library, see the [example](https://pub.dev/packages/sqlite3/example).

## Supported platforms

This library provides prebuilt versions of SQLite for the following platforms:

- __Android__: `armv7a`, `aarch64`, `x86`, `x64`.
- __iOS__: `arm64` (devices), `arm64` (simulator), `x64` (simulator).
- __macOS__: `arm64`, `x64`.
- __Linux__: `armv7`, `aarch64`, `x64`, `x86`, `riscv64gc`.
- __Windows__: `aarch64`, `x64`, `x86`.

For more information, see [hook options](./doc/hook.md).

In addition to native platforms, this package supports running on the web by accessing a sqlite3
build compiled to WebAssembly.
Web support is only officially supported for `dartdevc` and `dart2js`. Support
for `dart2wasm` [is experimental and incomplete](https://github.com/simolus3/sqlite3.dart/issues/230).
For more information, see [web support](#wasm-web-support) below.

On all supported platforms, you can also use SQLite3MultipleCiphers instead of SQLite to encrypt
databases. The [hook options page](./doc/hook.md) describe this setup.

## Supported datatypes

When binding parameters to queries, the supported types are `ìnt`,
`double`, `String`, `List<int>` (for `BLOB`) and `null`.
Result sets will use the same set of types.
On the web (but only on the web), `BigInt` is supported as well.

## WASM (web support)

This package experimentally supports being used on the web with a bit of setup.
The web version binds to a custom version of sqlite3 compiled to WebAssembly without
Emscripten or any JavaScript glue code.

Please note that stable web support for `package:sqlite3` is restricted to Dart
being compiled to JavaScript. Support for `dart2wasm` is experimental. The API
is identical, but the implementation [is severely limited](https://github.com/simolus3/sqlite3.dart/issues/230).

### Setup

To use this package on the web, you need:

- The sqlite3 library compiled as a WebAssembly module, available from the
  [GitHub releases](https://github.com/simolus3/sqlite3.dart/releases) of this package.
  Note that, for this package, __sqlite3 has to be compiled in a special way__.
  Existing WebAssembly files from e.g. sql.js will not work with `package:sqlite3/wasm.dart`.
  You can also see [this directory](https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3_wasm_build)
  for the build files to compile this yourself.
- A file system implementation, since websites can't by default access the host's file system.
 This package provides `InMemoryFileSystem` and an `IndexedDbFileSystem` implementation.

After putting `sqlite3.wasm` under the `web/` directory of your project, you can
open and use `sqlite3` like this:

```dart
import 'package:http/http.dart' as http;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

Future<WasmSqlite3> loadSqlite() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fileSystem = await IndexedDbFileSystem.open(dbName: 'my_app');
  sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);
  return sqlite;
}
```

The returned `WasmSqlite3` has an interface compatible to that of the standard `sqlite3` field
in `package:sqlite3/sqlite3.dart`, databases can be opened in similar ways.

An example for such web folder is in `example/web/` of this repo.
To view the example, copy a compiled `sqlite3.wasm` file to `web/sqlite3.wasm` in this directory.
Then, run `dart run build_runner serve example:8080` and visit `http://localhost:8080/web/` in a browser.

Another `../examples/multiplatform/` uses common interface to `sqlite3` on web and native platforms.
To run this example, merge its files into a Flutter app.

### Sharing code between web and a Dart VM

The `package:sqlite3/common.dart` library defines common interfaces that are implemented by both
the FFI-based native version in `package:sqlite3/sqlite3.dart` and the experimental WASM
version in `package:sqlite3/wasm.dart`.
By having shared code depend on the common interfaces, it can be used for both native and web
apps.

### Web encryption

Starting from version 2.6.0, `package:sqlite3/wasm.dart` supports loading a compiled version of
[SQLite Multiple Ciphers](https://utelle.github.io/SQLite3MultipleCiphers/) providing encryption
support for the web.
Please note that this variant is not currently tested as well as the regular SQLite version.
For this reason, using SQLite Multiple Ciphers with `package:sqlite3/wasm.dart` should be considered
experimental for the time being.

To test the encryption integration, download `sqlite3mc.wasm` from the [releases](https://github.com/simolus3/sqlite3.dart/releases)
of this package and use that as a URL to load sqlite3 on the web:

```dart
final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3mc.wasm'));
sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);

final database = sqlite3.open('/database')
  ..execute("pragma key = 'test';"); // TODO: Replace key
```

### Testing

To run the tests of this package with wasm, either download the `sqlite3.wasm` file from the
GitHub releases to `example/web` or compile it yourself (see [build setup](../sqlite3_wasm_build/)).

To run tests on the Dart VM, Firefox and Chrome, use:

```
dart test -P full
```
