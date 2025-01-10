@Tags(['wasm'])
library;

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  test('can open databases with sqlite3mc', () async {
    final sqlite3 = await loadSqlite3WithoutVfs(encryption: true);
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);

    sqlite3.open('/test')
      ..execute('pragma key = "key"')
      ..execute('CREATE TABLE foo (bar TEXT) STRICT;')
      ..execute('INSERT INTO foo VALUES (?)', ['test'])
      ..dispose();

    final database = sqlite3.open('/test');
    expect(
      () => database.select('SELECT * FROM foo'),
      throwsA(isA<SqliteException>()
          .having((e) => e.message, 'message', contains('not a database'))),
    );

    database.execute('pragma key = "key"');
    expect(database.select('SELECT * FROM foo'), isNotEmpty);
  });
}
