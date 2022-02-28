# sqlite3

Provides Dart bindings to [SQLite](https://www.sqlite.org/index.html) via `dart:ffi`.

For an example on how to use this library from Dart, see the [example](https://pub.dev/packages/sqlite3/example).

## Supported platforms

You can use this library on any platform where you can obtain a `DynamicLibrary` of sqlite.

Here's how to use this library on the most popular platforms:

- __Android__: Flutter users can depend on the `sqlite3_flutter_libs` package to ship the latest sqlite3
  version with their app
- __iOS__: Contains a built-in version of sqlite that this package will use by default. 
  When using Flutter, you can also depend on `sqlite3_flutter_libs` to ship the latest
  sqlite3 version with your app.
- __Linux__: You need to install an additional package (like `libsqlite3-dev` on Debian), or you manually
  ship sqlite3 with your app (see below)
- __macOS__: Contains a built-in version of sqlite that this package will use by default.
  Also, you can depend on `sqlite3_flutter_libs` if you want to include the latest
  sqlite3 version with your app.
- __Windows__: You need to manually ship sqlite3 with your app (see below)

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

## WASM

### Compiling

Note: Compiling sqlite3 to WebAssembly is not necessary for users of this package,
just grab the `.wasm` from the latest release.

To compile the wasm binding, first download a recent sqlite3 amalgation
(say to `/tmp/sqlite/`).

You'll also need a clang toolchain capable of compiling to WebAssembly
and a libc suitable for it (I use wasi in `/usr/share/wasi-sysroot`).

Then, run

```
clang \
  --target=wasm32-unknown-wasi \
  --sysroot /usr/share/wasi-sysroot \
  -Iassets/wasm -I/tmp/sqlite/ \
  -Ofast -nostartfiles \
  -Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic \
  -D_HAVE_SQLITE_CONFIG_H -DSQLITE_API='__attribute__((visibility("default")))' \
  -o example/web/sqlite.wasm /tmp/sqlite/sqlite3.c assets/wasm/os_web.c
```
