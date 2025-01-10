import 'package:sqlite3/wasm.dart';
import 'package:test/scaffolding.dart';

Future<WasmSqlite3> loadSqlite3WithoutVfs({bool encryption = false}) async {
  final channel = spawnHybridUri('/test/wasm/asset_server.dart');
  final port = (await channel.stream.first as double).toInt();

  final filename = encryption ? 'sqlite3mc.wasm' : 'sqlite3.wasm';
  final sqliteWasm = Uri.parse('http://localhost:$port/example/web/$filename');

  return await WasmSqlite3.loadFromUrl(sqliteWasm);
}

Future<WasmSqlite3> loadSqlite3([VirtualFileSystem? defaultVfs]) async {
  final sqlite3 = await loadSqlite3WithoutVfs();
  sqlite3.registerVirtualFileSystem(
    defaultVfs ?? InMemoryFileSystem(),
    makeDefault: true,
  );
  return sqlite3;
}
