@Tags(['wasm'])

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'utils.dart';

Future<void> main() async {
  group('indexed db', () {
    test('with proper persistence', () async {
      final fileSystem = await IndexedDbFileSystem.open(dbName: 'test');
      final sqlite3 =
          await loadSqlite3(SqliteEnvironment(fileSystem: fileSystem));
      final database = sqlite3.open('test');
      expect(database.userVersion, 0);
      database.userVersion = 1;
      expect(database.userVersion, 1);

      database.execute('CREATE TABLE IF NOT EXISTS users ( '
          'id INTEGER NOT NULL, '
          'name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, '
          'password TEXT NOT NULL, '
          'user_id INTEGER NOT NULL, '
          'currentCompanyId INTEGER NULL REFERENCES companies (id), '
          'PRIMARY KEY (id));');

      final prepared = database.prepare('INSERT INTO users '
          '(id, name, email, password, user_id) VALUES (?, ?, ?, ?, ?)');

      for (var i = 0; i < 200; i++) {
        prepared.execute(
          [
            BigInt.from(i),
            'name',
            'email${BigInt.from(i)}',
            'password',
            BigInt.from(i),
          ],
        );
      }

      database.select('SELECT * FROM users').forEach((element) {
        print(element.values);
      });

      database.dispose();
      //await fileSystem.close();
      await Future<void>.delayed(const Duration(milliseconds: 5000));

      final fileSystem2 = await IndexedDbFileSystem.open(dbName: 'test');
      final sqlite32 =
          await loadSqlite3(SqliteEnvironment(fileSystem: fileSystem2));
      final database2 = sqlite32.open('test');
      expect(database2.userVersion, 1);

      database2.select('SELECT * FROM users').forEach((element) {
        print(element.values);
      });
    });
  });
}
