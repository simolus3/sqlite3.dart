# sqlite3

Provides Dart bindings to [SQLite](https://www.sqlite.org/index.html) via `dart:ffi`.

## Using this library

1. Make sure sqlite3 is available as a shared library in your environment (see
   [supported platforms](#supported-platforms) below).
2. Import `package:sqlite3/sqlite3.dart`.
3. Use `sqlite3.open()` to open a database file, or `sqlite3.openInMemory()` to
   open a temporary in-memory database.
4. Use `Database.execute` or `Database.prepare` to execute statements directly
   or by preparing them first.
5. Don't forget to close prepared statements or the database with `dispose()`
   if you no longer need it.

For a more complete example on how to use this library, see the [example](https://pub.dev/packages/sqlite3/example).

## Supported platforms

You can use this library on any platform where you can obtain a `DynamicLibrary` with symbols
from `sqlite3`.
In addition, this package supports running on the web by accessing a sqlite3
build compiled to WebAssembly.
Web support is only official supported for `dartdevc` and `dart2js`. Support
for `dart2wasm` [is experimental and incomplete](https://github.com/simolus3/sqlite3.dart/issues/230).

Here's how to use this library on the most popular platforms:

- __Android__: Flutter users can depend on the `sqlite3_flutter_libs` package to ship the latest sqlite3
  version with their app.
- __iOS__: Contains a built-in version of sqlite that this package will use by default.
  When using Flutter, you can also depend on `sqlite3_flutter_libs` to ship the latest
  sqlite3 version with your app.
- __Linux__: Flutter users can depend on `sqlite3_flutter_libs` to ship the latest sqlite3
  version with their app.
  Alternatively, or when not using Flutter, you can install sqlite3 as a package from your
  distributions package manager (like `libsqlite3-dev` on Debian), or you can manually ship
  sqlite3 with your app (see below).
- __macOS__: Contains a built-in version of sqlite that this package will use by default.
  Also, you can depend on `sqlite3_flutter_libs` if you want to include the latest
  sqlite3 version with your app.
- __Windows__: Contains a built-in version of sqlite (winsqlite3.dll) that this package will use by default.
  winsqlite is used by Windows OS components and as the backend of .NET database APIs,
  but is [otherwise undocumented](https://github.com/microsoft/win32metadata/issues/824#issuecomment-1067220882);
  so you may still want to provide a sqlite3 binary you control.
  Flutter users can depend on `sqlite3_flutter_libs` to ship the latest sqlite3
  version with their app.
  When not using Flutter, you can manually include sqlite3 (see below).
- __Web__: See [web support](#wasm-web-support) below.

On Android, iOS and macOS, you can depend on the `sqlcipher_flutter_libs` package to use
[SQLCipher](https://www.zetetic.net/sqlcipher/) instead of SQLite.
Just be sure to never depend on both `sqlcipher_flutter_libs` and `sqlite3_flutter_libs`!

When opting into the native assets SDK feature, you can also use the [`sqlite3_native_assets`](https://pub.dev/packages/sqlite3_native_assets)
package to replace `sqlite3_flutter_libs` and platform-specific build scripts with
a unified build that works on all Dart platforms!

### Manually providing sqlite3 libraries

Instead of using the sqlite3 library from the OS, you can also ship a custom sqlite3 library along
with your app. You can override the way this package looks for sqlite3 to instead use your custom
library.
For instance, if you release your own `sqlite3.so` next to your application, you could use:

```dart
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  open.overrideFor(OperatingSystem.linux, _openOnLinux);

  final db = sqlite3.openInMemory();
  // Use the database
  db.dispose();
}

DynamicLibrary _openOnLinux() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final libraryNextToScript = File(join(scriptDir.path, 'sqlite3.so'));
  return DynamicLibrary.open(libraryNextToScript.path);
}
```

Just be sure to first override the behavior and then use `sqlite3`.

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

Another `example/multiplatform/` uses common interface to `sqlite3` on web and native platforms.
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
GitHub releases to `example/web` or compile it yourself (see [compiling](#compiling) below).

To run tests on the Dart VM, Firefox and Chrome, use:

```
dart test -P full
```
