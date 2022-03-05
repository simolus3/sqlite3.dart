import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';

Future<void> main() async {
  final response = await http.get(Uri.parse('sqlite.wasm'));
  final sqlite = await WasmSqlite3.load(response.bodyBytes);

  print(sqlite.version);

  final db = sqlite.open('/var/x.db');

  db.createFunction(
    functionName: 'hello_from_dart',
    function: (args) {
      print(args);
      return 'custom dart functions!';
    },
  );

  final stmt = db.prepare('SELECT hello_from_dart(1) AS r;');
  print(stmt.select());

  db.execute('CREATE TABLE foo (x TEXT);');
  db.dispose();
}
