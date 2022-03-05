import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';
import 'package:wasm_interop/wasm_interop.dart';

Future<void> main() async {
  final response = await http.get(Uri.parse('sqlite.wasm'));
  final module = await Module.fromBytesAsync(response.bodyBytes);

/*
  for (final import in module.imports) {
    print('import ${import.module}/${import.name}');
  }

  for (final export in module.exports) {
    print('export ${export.name}');
  }
*/
  final sqlite = await WasmSqlite3.createAsync(module);

  print(sqlite.version);

  final db = sqlite.openInMemory();
  print(db.userVersion);
  db.createFunction(
    functionName: 'hello_from_dart',
    function: (args) => 'custom dart functions!',
  );

  final stmt = db.prepare('SELECT hello_from_dart() AS r;');
  print(stmt.select());
  db.dispose();
}