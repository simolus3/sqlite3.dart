import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/wasm.dart' show IndexedDbFileSystem, WasmSqlite3;

Future<CommonDatabase> openSqliteDb() async {
  const name = 'my_app';
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fileSystem = await IndexedDbFileSystem.open(dbName: name);
  sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);
  return sqlite.open(name);
}
