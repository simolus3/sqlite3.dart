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

  group('indexed db with legacy vfs', () {
    _testWith(() => IndexedDbFileSystem.load(_fsRoot));
    _testAccess(() => IndexedDbFileSystem.load(_fsRoot));
  });

  group('indexed db with vfs v2.0', () {
    _testWith(() => IndexedDbFileSystemV2.init(
        persistenceRoot: _fsRoot, dbName: _randomName()));
    _testV2Persistence();
  });

  group('basic persistence', () {
    test('basic persistence V1', () async {
      final fs = await IndexedDbFileSystem.load(_fsRoot);
      await _basicPersistence(fs);
    });

    test('basic persistence V2', () async {
      final fs = await IndexedDbFileSystemV2.init(dbName: _randomName());
      await _basicPersistence(fs);
    });
  });

  group('vfs v2.0 path normalization', () {
    _testPathNormalization();
  });
}

final _random = Random(DateTime.now().millisecond);
String _randomName() => _random.nextInt(0x7fffffff).toString();

Future<void> _disposeFileSystem(FileSystem fs) async {
  if (fs is IndexedDbFileSystemV2) {
    await fs.close();
    await IndexedDbFileSystemV2.deleteDatabase(fs.dbName);
  } else {
    fs.clear();
  }
}

Future<void> _runPathTest(String root, String path, String resolved) async {
  final fs = await IndexedDbFileSystemV2.init(
      persistenceRoot: root, dbName: _randomName());
  fs.createFile(path);
  final absPath = fs.absolutePath(fs.files().first);
  expect(absPath, resolved);
  await _disposeFileSystem(fs);
}

Future<void> _basicPersistence(FileSystem fs) async {
  fs.createFile('$_fsRoot/test');
  expect(fs.exists('$_fsRoot/test'), true);
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  final fs2 = await IndexedDbFileSystem.load(_fsRoot);
  expect(fs2.exists('$_fsRoot/test'), true);
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

  test('normalization', () async {
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
    expect(fs.files(), isEmpty);
    fs.createFile('$_fsRoot/foo.txt');
    expect(fs.exists('$_fsRoot/foo.txt'), isTrue);
    expect(fs.files(), ['$_fsRoot/foo.txt']);
    fs.deleteFile('$_fsRoot/foo.txt');
    expect(fs.files(), isEmpty);
  });

  test('can create and delete multiple files', () {
    for (var i = 1; i <= 10; i++) {
      fs.createFile('$_fsRoot/foo$i.txt');
    }
    expect(fs.files(), hasLength(10));
    for (final f in fs.files()) {
      fs.deleteFile(f);
    }
    expect(fs.files(), isEmpty);
  });

  test('can create files and clear fs', () {
    for (var i = 1; i <= 10; i++) {
      fs.createFile('$_fsRoot/foo$i.txt');
    }
    expect(fs.files(), hasLength(10));
    fs.clear();
    expect(fs.files(), isEmpty);
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

Future<void> _testAccess(Future<IndexedDbFileSystem> Function() open) async {
  late IndexedDbFileSystem fs;

  setUp(() async => fs = await open());
  tearDown(() => _disposeFileSystem(fs));

  test('access permissions', () {
    expect(() => fs.exists('/test2/foo.txt'),
        throwsA(isA<FileSystemAccessException>()));
    expect(() => fs.createFile('/test2/foo.txt'),
        throwsA(isA<FileSystemAccessException>()));
    expect(() => fs.write('/test2/foo.txt', Uint8List(0), 0),
        throwsA(isA<FileSystemAccessException>()));
    expect(() => fs.sizeOfFile('/test2/foo.txt'),
        throwsA(isA<FileSystemAccessException>()));
    expect(() => fs.read('/test2/foo.txt', Uint8List(0), 0),
        throwsA(isA<FileSystemAccessException>()));
    expect(() => fs.truncateFile('/test2/foo.txt', 0),
        throwsA(isA<FileSystemAccessException>()));
    expect(() => fs.deleteFile('/test2/foo.txt'),
        throwsA(isA<FileSystemAccessException>()));
    expect(fs.createTemporaryFile(), '/tmp/0');
  });
}

void _testV2Persistence() {
  test('advanced persistence', () async {
    final data = Uint8List.fromList([for (var i = 0; i < 255; i++) i]);
    final dbName = _randomName();

    await expectLater(
      () async {
        final databases = (await IndexedDbFileSystemV2.databases())
            .map((e) => e.name)
            .toList();
        return !databases.contains(dbName);
      }(),
      completion(true),
      reason: 'There must be no database named dbName at the beginning',
    );

    final db1 = await IndexedDbFileSystemV2.init(dbName: dbName);
    expect(db1.files().length, 0, reason: 'db1 is not empty');

    db1.createFile('test');
    db1.write('test', data, 0);
    await db1.flush();
    expect(db1.files().length, 1, reason: 'There must be only one file in db1');
    expect(db1.exists('test'), true, reason: 'The test file must exist in db1');

    final db2 = await IndexedDbFileSystemV2.init(dbName: dbName);
    expect(db2.files().length, 1, reason: 'There must be only one file in db2');
    expect(db2.exists('test'), true, reason: 'The test file must exist in db2');

    final read = Uint8List(255);
    db2.read('test', read, 0);
    expect(_listEquality.equals(read, data), true,
        reason: 'The data written and read do not match');

    await db2.clear();
    expect(db2.files().length, 0, reason: 'There must be no files in db2');
    expect(db1.files().length, 1, reason: 'There must be only one file in db1');
    await db1.sync();
    expect(db1.files().length, 0, reason: 'There must be no files in db1');

    await db1.close();
    await db2.close();

    await expectLater(() => db1.sync(), throwsA(isA<FileSystemException>()));
    await expectLater(() => db2.sync(), throwsA(isA<FileSystemException>()));

    await IndexedDbFileSystemV2.deleteDatabase(dbName);

    await expectLater(
      () async {
        final databases = (await IndexedDbFileSystemV2.databases())
            .map((e) => e.name)
            .toList();
        return !databases.contains(dbName);
      }(),
      completion(true),
      reason: 'There can be no database named dbName at the end',
    );
  });
}
