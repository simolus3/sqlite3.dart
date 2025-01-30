Definitions and common interfaces that are implemented by both the native
and the web-specific bindings to SQLite.

Restricting your usage of the sqlite3 package to `package:sqlite3/common.dart`
means that your code can run on all platforms.
However, this doesn't give you access to the actual implementations that are part
of the native and web implementations.
You can write most of your database code with the common definitions and then use
conditional imports to make an implementation available. For this, create three files:

1. `database_stub.dart`.
2. `database_native.dart`.
3. `datbaase_web.dart`.

The content of these files depends on your needs, but could look like this:

```dart
// database_stub.dart
import 'package:sqlite3/common.dart';

Future<CommonDatabase> openDatabase() async {
  throw UnsupportedError('Unknown platform');
}
```

```dart
// database_native.dart
import 'package:sqlite3/sqlite3.dart';

Future<CommonDatabase> openDatabase() async {
  final path = await pickDatabasePath(); // e.g. with package:path_provider
  return sqlite3.open(path);
}
```

```dart
// database_web.dart
import 'package:sqlite3/wasm.dart';

Future<CommonDatabase> openDatabase() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fs = await IndexedDbFileSystem.open(dbName: 'app.db');
  sqlite.registerVirtualFileSystem(fs, makeDefault: true);
  return sqlite.open('/app.db');
}
```

With those files, you can use a conditional imports to support both web and native platforms:

```dart
import 'database_stub.dart'
    if (dart.library.io) 'database_native.dart'
    if (dart.library.js_interop) 'database_web.dart';
```
