import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_native_assets/sqlite3_native_assets.dart';

void main() {
  final sqlite3 = sqlite3Native;
  print('Using sqlite3 ${sqlite3.version}');

  // Create a new in-memory database. To use a database backed by a file, you
  // can replace this with sqlite3.open(yourFilePath).
  final db = sqlite3.openInMemory();
  final db2 = sqlite3.openInMemory();

  final session = sqlite3.createSession(db, 'main');

  print('session: ${session.runtimeType}');

  // Create a table and insert some data
  db.execute('''
    CREATE TABLE artists (
      id INTEGER NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    );
  ''');
  db2.execute('''
    CREATE TABLE artists (
      id INTEGER NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    );
  ''');

  session.attach('artists');
  print('attached to artists');

  // Prepare a statement to run it multiple times:
  final stmt = db.prepare('INSERT INTO artists (name) VALUES (?)');
  stmt
    ..execute(['The Beatles'])
    ..execute(['Led Zeppelin'])
    ..execute(['The Who'])
    ..execute(['Nirvana']);

  // Dispose a statement when you don't need it anymore to clean up resources.
  stmt.dispose();

  // final changeset = session.changeset();
  // print('changeset: ${changeset.lengthInBytes} bytes');

  final changeset = session.patchset();
  print('patchset: ${changeset.lengthInBytes} bytes');

  // apply changes
  db2.changesetApply(
    changeset,
    // conflict: (ctx, eConflict, iter) {
    //   print('conflict: $eConflict');
    //   return ApplyChangesetRule.omit;
    // },
    // filter: (ctx, table) {
    //   print('filter: $table');
    //   return 1;
    // },
  );

  // query the database using a simple select statement
  final result = db2.select('SELECT * FROM artists');
  for (final row in result) {
    print('cs: Artist[id: ${row['id']}, name: ${row['name']}]');
  }

  session.delete();
  print('deleted session');

  // You can run select statements with PreparedStatement.select, or directly
  // on the database:
  final ResultSet resultSet = db.select(
    'SELECT * FROM artists WHERE name LIKE ?',
    ['The %'],
  );

  // You can iterate on the result set in multiple ways to retrieve Row objects
  // one by one.
  for (final Row row in resultSet) {
    print('Artist[id: ${row['id']}, name: ${row['name']}]');
  }

  // Register a custom function we can invoke from sql:
  db.createFunction(
    functionName: 'dart_version',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) => Platform.version,
  );
  print(db.select('SELECT dart_version()'));

  // Don't forget to dispose the database to avoid memory leaks
  db.dispose();
}
