@Tags(['wasm'])
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'utils.dart';

const _fsRoot = '/test';

Future<void> main() async {
  group('in memory', () {
    _testWith(() => FileSystem.inMemory());
  });

  group('indexed db', () {
    _testWith(() => IndexedDbFileSystem.open(dbName: _randomName()));

    test('with proper persistence', () async {
      final data = Uint8List.fromList(List.generate(255, (i) => i));
      final dbName = _randomName();

      await expectLater(IndexedDbFileSystem.databases(),
          completion(anyOf(isNull, isNot(contains(dbName)))),
          reason: 'Database $dbName should not exist');

      final db1 = await IndexedDbFileSystem.open(dbName: dbName);
      expect(db1.files.length, 0, reason: 'db1 is not empty');

      db1.createFile('test');
      db1.write('test', data, 0);
      db1.truncateFile('test', 128);
      await db1.flush();
      expect(db1.files, ['test'], reason: 'File must exist');
      await db1.close();

      final db2 = await IndexedDbFileSystem.open(dbName: dbName);
      expect(db2.files, ['test'], reason: 'Single file must be in db2 as well');

      final read = Uint8List(128);
      expect(db2.read('test', read, 0), 128, reason: 'Should read 128 bytes');
      expect(read, List.generate(128, (i) => i),
          reason: 'The data written and read do not match');

      await db2.clear();
      expect(db2.files, isEmpty, reason: 'There must be no files in db2');

      await db2.close();
      await expectLater(
          Future.sync(db2.clear), throwsA(isA<FileSystemException>()));

      await IndexedDbFileSystem.deleteDatabase(dbName);
      await expectLater(IndexedDbFileSystem.databases(),
          completion(anyOf(isNull, isNot(contains(dbName)))),
          reason: 'Database $dbName should not exist in the end');
    });

    test('example with frequent writes', () async {
      final fileSystem = await IndexedDbFileSystem.open(dbName: 'test');
      final sqlite3 =
          await loadSqlite3(SqliteEnvironment(fileSystem: fileSystem));
      final database = sqlite3.open('test');
      expect(database.userVersion, 0);
      database.userVersion = 1;
      expect(database.userVersion, 1);

      database.execute('CREATE TABLE IF NOT EXISTS users ( '
          'id INTEGER NOT NULL, '
          'name TEXT NOT NULL, '
          'email TEXT NOT NULL UNIQUE, '
          'user_id INTEGER NOT NULL, '
          'PRIMARY KEY (id));');

      final prepared = database.prepare('INSERT INTO users '
          '(id, name, email, user_id) VALUES (?, ?, ?, ?)');

      for (var i = 0; i < 200; i++) {
        prepared.execute(
          [
            BigInt.from(i),
            'name',
            'email${BigInt.from(i)}',
            BigInt.from(i),
          ],
        );
      }

      expect(database.select('SELECT * FROM users'), hasLength(200));

      database.dispose();

      // file-system should save reasonably quickly
      await fileSystem.close().timeout(const Duration(seconds: 1));

      final fileSystem2 = await IndexedDbFileSystem.open(dbName: 'test');
      final sqlite32 =
          await loadSqlite3(SqliteEnvironment(fileSystem: fileSystem2));
      final database2 = sqlite32.open('test');
      expect(database2.userVersion, 1);
      expect(database2.select('SELECT * FROM users'), hasLength(200));
    });

    test('can delete and re-create files', () async {
      final dbName = _randomName();
      final fs = await IndexedDbFileSystem.open(dbName: dbName);
      addTearDown(() async {
        await fs.close();
        return IndexedDbFileSystem.deleteDatabase(dbName);
      });

      fs.createFile('foo');
      fs.write('foo', Uint8List.fromList([1, 2, 3]), 0);
      await fs.flush();

      fs.deleteFile('foo');
      await fs.flush();

      fs.createFile('foo');
      fs.write('foo', Uint8List.fromList([4, 5, 6]), 0);
      await fs.flush();

      final target = Uint8List(3);
      fs.read('foo', target, 0);
      expect(target, [4, 5, 6]);
    });
  });
}

final _random = Random(DateTime.now().millisecond);
String _randomName() => _random.nextInt(0x7fffffff).toString();

Future<void> _disposeFileSystem(FileSystem fs, [String? name]) async {
  if (fs is IndexedDbFileSystem) {
    await fs.close();
    if (name != null) await IndexedDbFileSystem.deleteDatabase(name);
  } else {
    await Future.sync(fs.clear);
  }
}

Future<void> _testWith(FutureOr<FileSystem> Function() open) async {
  late FileSystem fs;

  setUp(() async {
    fs = await open();
  });

  tearDown(() => _disposeFileSystem(fs));

  test('can create files', () {
    expect(fs.exists('$_fsRoot/foo.txt'), isFalse);
    expect(fs.files, isEmpty);
    fs.createFile('$_fsRoot/foo.txt');
    expect(fs.exists('$_fsRoot/foo.txt'), isTrue);
    expect(fs.files, ['$_fsRoot/foo.txt']);
    fs.deleteFile('$_fsRoot/foo.txt');
    expect(fs.files, isEmpty);
  });

  test('can create and delete multiple files', () {
    for (var i = 1; i <= 10; i++) {
      fs.createFile('$_fsRoot/foo$i.txt');
    }
    expect(fs.files, hasLength(10));
    for (final f in fs.files) {
      fs.deleteFile(f);
    }
    expect(fs.files, isEmpty);
  });

  test('reads and writes', () {
    expect(fs.exists('$_fsRoot/foo.txt'), isFalse);
    fs.createFile('$_fsRoot/foo.txt');
    addTearDown(() => fs.deleteFile('$_fsRoot/foo.txt'));

    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), isZero);

    fs.truncateFile('$_fsRoot/foo.txt', 1024);
    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), 1024);

    fs.truncateFile('$_fsRoot/foo.txt', 600);
    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), 600);

    fs.truncateFile('$_fsRoot/foo.txt', 0);
    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), 0);

    fs.write('$_fsRoot/foo.txt', Uint8List.fromList([1, 2, 3]), 0);
    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), 3);

    final target = Uint8List(3);
    expect(fs.read('$_fsRoot/foo.txt', target, 0), 3);
    expect(target, [1, 2, 3]);
  });

  test('can create files and clear fs', () async {
    for (var i = 1; i <= 10; i++) {
      fs.createFile('$_fsRoot/foo$i.txt');
    }
    expect(fs.files, hasLength(10));
    await Future.sync(fs.clear);
    expect(fs.files, isEmpty);
  });
}
