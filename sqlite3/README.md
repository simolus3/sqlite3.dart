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
is identical, but the implementation [is severly limited](https://github.com/simolus3/sqlite3.dart/issues/230).

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
Then, run `dart run build_runner serve example:8080` and  visit `http://localhost:8080/web/` in a browser.

Another `example/multiplatform/` uses common interface to `sqlite3` on web and native platforms.
To run this example, merge its files into a Flutter app.

### Sharing code between web and a Dart VM

The `package:sqlite3/common.dart` library defines common interfaces that are implemented by both
the FFI-based native version in `package:sqlite3/sqlite3.dart` and the experimental WASM
version in `package:sqlite3/wasm.dart`.
By having shared code depend on the common interfaces, it can be used for both native and web
apps.

### Testing

To run the tests of this package with wasm, either download the `sqlite3.wasm` file from the
GitHub releases to `example/web` or compile it yourself (see [compiling](#compiling) below).

To run tests on the Dart VM, Firefox and Chrome, use:

```
dart test -P full
```

### Compiling

Note: Compiling sqlite3 to WebAssembly is not necessary for users of this package,
just grab the `.wasm` from the latest release on GitHub.

This section describes how to compile the WebAssembly modules from source. This
uses a LLVM-based toolchain with components of the WASI SDK for C runtime components.

#### Setup

##### Linux

On Linux, you need a LLVM based toolchain capable of compiling to WebAssembly.
On Arch Linux, the `wasi-compiler-rt` and `wasi-libc` packages are enough for this.
On other distros, you may have to download the sysroot and compiler builtins from their
respective package managers or directly from the WASI SDK releases.

With wasi in `/usr/share/wasi-sysroot` and the default clang compiler having the
required builtins, you can setup the build with:

```
cmake -S assets/wasm -B .dart_tool/sqlite3_build
```

##### macOS

On macOS, I'm installing `cmake`, `llvm` and `binaryen` through Homebrew. Afterwards, you can download the
wasi sysroot and the compiler runtimes from the Wasi SDK project:

```
curl -sL https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-22/libclang_rt.builtins-wasm32-wasi-22.0.tar.gz | \
  tar x -zf - -C /opt/homebrew/opt/llvm/lib/clang/18*

curl -sS -L https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-22/wasi-sysroot-22.0.tar.gz | \
  sudo tar x -zf - -C /opt
```

Replace `clang/18` with the correct directory if you're using a different version.

Then, set up the build with

```
cmake -Dwasi_sysroot=/opt/wasi-sysroot -Dclang=/opt/homebrew/opt/llvm/bin/clang -S assets/wasm -B .dart_tool/sqlite3_build
```

#### Building

In this directory, run:

```
cmake --build .dart_tool/sqlite3_build/ -t output -j
```

The `output` target copies `sqlite3.wasm` and `sqlite3.debug.wasm` to `example/web`.

(Of course, you can also run the build in any other directory than `.dart_tool/sqite3_build` if you want to).

### Customizing the WASM module

The build scripts in this repository, which are also used for the default distribution of `sqlite3.wasm`
attached to releases, are designed to mirror the options used by `sqlite3_flutter_libs`.
If you want to use different options, or include custom extensions in the WASM module, you can customize
the build setup.

To use regular sqlite3 sources with different compile-time options, alter `assets/wasm/sqlite_cfg.h` and
re-run the build as described in [compiling](#compiling).
Including additional extensions written in C is possible by adapting the `CMakeLists.txt` in
`assets/wasm`.

A simple example demonstrating how to include Rust-based extensions is included in `example/custom_wasm_build`.
The readme in that directory explains the build process in detail, but you still need the WASI/Clang toolchains
described in the [setup section](#linux).
