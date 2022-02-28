import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';
import 'package:wasm_interop/wasm_interop.dart';

Future<WasmSqlite3> loadSqlite3() async {
  // Tests run under `localhost:port/secret/packages/test/src/...`
  final secret = Uri.base.pathSegments.first;
  print(Uri.parse('/$secret/assets/test.wasm'));

  final response = await http.get(Uri.parse('/$secret/assets/test.wasm'));
  if (response.statusCode != 200) {
    throw StateError(
        'Could not load module (${response.statusCode} ${response.body})');
  }

  final module = await Module.fromBytesAsync(response.bodyBytes);
  return WasmSqlite3.createAsync(module);
}
