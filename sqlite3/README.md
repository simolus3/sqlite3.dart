# sqlite3

Provides Dart bindings to [SQLite](https://www.sqlite.org/index.html) via `dart:ffi`.

For an example on how to use this library from Dart, see the [example](https://pub.dev/packages/sqlite3/example).

## Supported platforms

You can use this library on any platform where you can obtain a `DynamicLibrary` with symbols
from `sqlite3`.
In addition, this package experimentally supports the web through WebAssembly.

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
- __Windows__: Flutter users can depend on `sqlite3_flutter_libs` to ship the latest sqlite3
  version with their app.
  When not using Flutter, you need to manually include sqlite3 (see below).
- __Web__: See [web support](#wasm-web-support) below.

On Android, iOS and macOS, you can depend on the `sqlcipher_flutter_libs` package to use
[SQLCipher](https://www.zetetic.net/sqlcipher/) instead of SQLite.
Just be sure to never depend on both `sqlcipher_flutter_libs` and `sqlite3_flutter_libs`!

### Manually providing sqlite3 libraries

Instead of using the sqlite3 library from the OS, you can also ship a custom sqlite3 library along
with your app. You can override the way this package looks for sqlite3 to instead use your custom
library.
For instance, if you release your own `sqlite3.so` next to your application, you could use:

```dart
import 'dart:ffi';
import 'dart:io';

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
  final libraryNextToScript = File('${scriptDir.path}/sqlite3.so');
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

### Setup

To use this package on the web, you need:

- The sqlite3 library compiled as a WebAssembly module, available from the
  [GitHub releases](https://github.com/simolus3/sqlite3.dart/releases) of this package.
  Note thaat, for this package, __sqlite3 has to be compiled in a special way__.
  Existing WebAssembly files from e.g. sql.js will not work with `package:sqlite3/wasm.dart`.
- A file system implementation, since websites can't by default access the host's file system.
 This package provides `FileSystem.inMemory()` and an `IndexedDbFileSystem` implementation.

After putting `sqlite3.wasm` under the `web/` directory of your project, you can
open and use `sqlite3` like this:

```dart
import 'package:http/http.dart' as http;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

Future<WasmSqlite3> loadSqlite() async {
  final response = await http.get(Uri.parse('sqlite.wasm'));
  final fs = await IndexedDbFileSystem.load('/');

  return await WasmSqlite3.load(
      response.bodyBytes, SqliteEnvironment(fileSystem: fs));
}
```

The returned `WasmSqlite3` has an interface compatible to that of the standard `sqlite3` field
in `package:sqlite3/sqlite3.dart`, databases can be opened in similar ways.

An example for such web folder is in `example/web/` of this repo.
To view the example, copy a compiled `sqlite3.wasm` file to `web/sqlite3.wasm` in this directory.
Then, run `dart run build_runner serve example:8080` and  visit `http://localhost:8080/web/` in a browser.

### Sharing code between web and a Dart VM

The `package:sqlite3/common.dart` library defines common interfaces that are implemented by both
the FFI-based native version in `package:sqlite3/sqlite3.dart` and the experimental WASM
version in `package:sqlite3/wasm.dart`.
By having shared code depend on the common interfaces, it can be used for both native and web
apps.

### Compiling

Note: Compiling sqlite3 to WebAssembly is not necessary for users of this package,
just grab the `.wasm` from the latest release on GitHub.

You'll need a clang toolchain capable of compiling to WebAssembly and a libc
suitable for it (I use wasi in `/usr/share/wasi-sysroot`).

Create a build directory, then run
```
cmake <path/to/clone>/sqlite3/assets/wasm --toolchain <path/to/clone>/sqlite3/assets/wasm/toolchain.cmake
make -j output
```
