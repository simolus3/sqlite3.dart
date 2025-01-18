import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_test/sqlite3_test.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:file/local.dart';

void main() {
  late TestSqliteFileSystem vfs;

  setUp(() {
    vfs = TestSqliteFileSystem(fs: const LocalFileSystem());
    sqlite3.registerVirtualFileSystem(vfs, makeDefault: false);
  });
  tearDown(() => sqlite3.unregisterVirtualFileSystem(vfs));

  Database withDatabase(Database db) {
    addTearDown(db.dispose);
    return db;
  }

  Database inMemory() => withDatabase(sqlite3.openInMemory(vfs: vfs.name));
  Database onDisk(String path) =>
      withDatabase(sqlite3.open(path, vfs: vfs.name));

  test('reports fake time', () {
    final moonLanding = DateTime.utc(1969, 7, 20, 20, 18, 04);

    FakeAsync(initialTime: moonLanding).run((async) {
      final db = inMemory();

      expect(db.select('SELECT current_time AS r'), [
        {'r': '20:18:04'}
      ]);
      expect(db.select('SELECT current_date AS r'), [
        {'r': '1969-07-20'}
      ]);
      expect(db.select('SELECT current_timestamp AS r'), [
        {'r': '1969-07-20 20:18:04'}
      ]);
    });
  });

  test('use fake cwd from io overrides', () async {
    await d.dir('foo').create();
    final cwd = Directory(d.path('foo'));

    IOOverrides.runZoned(() {
      final db = onDisk('test.db');
      db.execute('CREATE TABLE foo (bar);');
    }, getCurrentDirectory: () => cwd);

    await d.dir('foo', [
      d.FileDescriptor.binaryMatcher(
          'test.db',
          predicate((bytes) {
            final firstBytes = (bytes as List<int>).sublist(0, 15);
            return utf8.decode(firstBytes) == 'SQLite format 3';
          }, 'starts with sqlite header')),
    ]).validate();
  });
}
