import 'dart:html';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';

Future<void> main() async {
  final fs = FileSystem.inMemory(); //await IndexedDbFileSystem.load('/db/');

/*
  final data = Uint8List(4096 * 2);
  fs.read('/tmp/test.db', data, 0);
  final blob = Blob(<Uint8List>[data]);
  final a = AnchorElement()
    ..href = Url.createObjectUrlFromBlob(blob)
    ..download = 'test.db';
  document.body!.append(a);
  a.click();
  */

  final response = await http.get(Uri.parse('sqlite.wasm'));
  final sqlite = await WasmSqlite3.load(
      response.bodyBytes, SqliteEnvironment(fileSystem: fs));

  print(sqlite.version);

  var db = sqlite.open('/db/test.db');

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

  print('new connection');
  db = sqlite.open('/db/test.db');
  db.execute('CREATE TABLE foo (x TEXT);');
}
