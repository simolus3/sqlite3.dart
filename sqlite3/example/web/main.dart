import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';
import 'package:wasm_interop/wasm_interop.dart';

void main() async {
  final response = await http.get(Uri.parse('sqlite.wasm'));
  final module = await Module.fromBytesAsync(response.bodyBytes);

  for (final export in module.exports) {
    print(export.name);
  }

  final sqlite = await WasmSqlite3.createAsync(module);

  print(sqlite.version);
}
