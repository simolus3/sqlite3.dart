import 'package:sqlite3/wasm.dart';
import 'package:test/scaffolding.dart';

Future<WasmSqlite3> loadSqlite3([SqliteEnvironment? environment]) async {
  final channel = spawnHybridUri('/test/wasm/asset_server.dart');
  final port = await channel.stream.first as int;

  final sqliteWasm =
      Uri.parse('http://localhost:$port/example/web/sqlite3.wasm');

  return WasmSqlite3.loadFromUrl(sqliteWasm, environment: environment);
}
