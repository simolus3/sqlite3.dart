@Tags(['wasm'])
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

const _fsRoot = '/test';
const _listEquality = DeepCollectionEquality();

Future<void> main() async {
  group('in memory', () {
    _testWith(FileSystem.inMemory);
  });

  group('indexed db', () {
    _testWith(() => IndexedDbFileSystem.init(
        persistenceRoot: _fsRoot, dbName: _randomName()));
    _testPersistence();
  });

  group('path normalization', () {
    _testPathNormalization();
  });
}

final _random = Random(DateTime.now().millisecond);
String _randomName() => _random.nextInt(0x7fffffff).toString();

Future<void> _disposeFileSystem(FileSystem fs) async {
  if (fs is IndexedDbFileSystem) {
    await fs.close();
    await IndexedDbFileSystem.deleteDatabase(fs.dbName);
  } else {
    fs.clear();
  }
}

Future<void> _runPathTest(String root, String path, String resolved) async {
  final fs = await IndexedDbFileSystem.init(
      persistenceRoot: root, dbName: _randomName());
  fs.createFile(path);
  final absPath = fs.absolutePath(fs.files.first);
  expect(absPath, resolved);
  await _disposeFileSystem(fs);
}

Future<void> _testPathNormalization() async {
  test('persistenceRoot', () async {
    await _runPathTest('', 'test', '/test');
    await _runPathTest('/', 'test', '/test');
    await _runPathTest('//', 'test', '/test');
    await _runPathTest('./', 'test', '/test');
    await _runPathTest('././', 'test', '/test');
    await _runPathTest('../', 'test', '/test');
  });

  test('path', () async {
    await _runPathTest('', 'test', '/test');
    await _runPathTest('/', '../test', '/test');
    await _runPathTest('/', '../test/../../test', '/test');
    await _runPathTest('/', '/test1/test2', '/test1/test2');
    await _runPathTest('/', '/test1/../test2', '/test2');
    await _runPathTest('/', '/test1/../../test2', '/test2');
  });

  test('is directory', () async {
    await expectLater(_runPathTest('/', 'test/', '/test'),
        throwsA(isA<FileSystemException>()));
    await expectLater(_runPathTest('/', 'test//', '/test'),
        throwsA(isA<FileSystemException>()));
    await expectLater(_runPathTest('/', '/test//', '/test'),
        throwsA(isA<FileSystemException>()));
    await expectLater(_runPathTest('/', 'test/.', '/test'),
        throwsA(isA<FileSystemException>()));
    await expectLater(_runPathTest('/', 'test/..', '/test'),
        throwsA(isA<FileSystemException>()));
  });
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

  test('can create files and clear fs', () {
    for (var i = 1; i <= 10; i++) {
      fs.createFile('$_fsRoot/foo$i.txt');
    }
    expect(fs.files, hasLength(10));
    fs.clear();
    expect(fs.files, isEmpty);
  });

  test('reads and writes', () {
    expect(fs.exists('$_fsRoot/foo.txt'), isFalse);
    fs.createFile('$_fsRoot/foo.txt');
    addTearDown(() => fs.deleteFile('$_fsRoot/foo.txt'));

    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), isZero);

    fs.truncateFile('$_fsRoot/foo.txt', 123);
    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), 123);

    fs.truncateFile('$_fsRoot/foo.txt', 0);
    fs.write('$_fsRoot/foo.txt', Uint8List.fromList([1, 2, 3]), 0);
    expect(fs.sizeOfFile('$_fsRoot/foo.txt'), 3);

    final target = Uint8List(3);
    expect(fs.read('$_fsRoot/foo.txt', target, 0), 3);
    expect(target, [1, 2, 3]);
  });
}

void _testPersistence() {
  test('Properly persist into IndexedDB', () async {
    final data = Uint8List.fromList([for (var i = 0; i < 255; i++) i]);
    final dbName = _randomName();

    await expectLater(
      () async {
        final databases = (await IndexedDbFileSystem.databases())
            ?.map((e) => e.name)
            .toList();
        return databases == null ? true : !databases.contains(dbName);
      }(),
      completion(true),
      reason: 'There must be no database named dbName at the beginning',
    );

    final db1 = await IndexedDbFileSystem.init(dbName: dbName);
    expect(db1.files.length, 0, reason: 'db1 is not empty');

    db1.createFile('test');
    db1.write('test', data, 0);
    await db1.flush();
    expect(db1.files.length, 1, reason: 'There must be only one file in db1');
    expect(db1.exists('test'), true, reason: 'The test file must exist in db1');

    final db2 = await IndexedDbFileSystem.init(dbName: dbName);
    expect(db2.files.length, 1, reason: 'There must be only one file in db2');
    expect(db2.exists('test'), true, reason: 'The test file must exist in db2');

    final read = Uint8List(255);
    db2.read('test', read, 0);
    expect(_listEquality.equals(read, data), true,
        reason: 'The data written and read do not match');

    await db2.clear();
    expect(db2.files.length, 0, reason: 'There must be no files in db2');
    expect(db1.files.length, 1, reason: 'There must be only one file in db1');
    await db1.sync();
    expect(db1.files.length, 0, reason: 'There must be no files in db1');

    await db1.close();
    await db2.close();

    await expectLater(() => db1.sync(), throwsA(isA<FileSystemException>()));
    await expectLater(() => db2.sync(), throwsA(isA<FileSystemException>()));

    await IndexedDbFileSystem.deleteDatabase(dbName);

    await expectLater(
      () async {
        final databases = (await IndexedDbFileSystem.databases())
            ?.map((e) => e.name)
            .toList();
        return databases == null ? true : !databases.contains(dbName);
      }(),
      completion(true),
      reason: 'There can be no database named dbName at the end',
    );
  });
}