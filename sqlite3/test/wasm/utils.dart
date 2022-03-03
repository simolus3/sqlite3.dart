import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';
import 'package:test/scaffolding.dart';
import 'package:wasm_interop/wasm_interop.dart';

Future<WasmSqlite3> loadSqlite3() async {
  final channel = spawnHybridUri('/test/wasm/asset_server.dart');
  final port = await channel.stream.first as int;

  final sqliteWasm =
      Uri.parse('http://localhost:$port/example/web/sqlite.wasm');
  print(sqliteWasm);

  final response = await http.get(sqliteWasm);
  if (response.statusCode != 200) {
    throw StateError(
        'Could not load module (${response.statusCode} ${response.body})');
  }

  final module = await Module.fromBytesAsync(response.bodyBytes);
  return WasmSqlite3.createAsync(module);
}
