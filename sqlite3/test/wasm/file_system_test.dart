@Tags(['wasm'])
import 'dart:async';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

const _fsRoot = '/test/';

void main() {
  group('in memory', () {
    _testWith(FileSystem.inMemory);
  });

  group('indexed db', () {
    _testWith(() => IndexedDbFileSystem.load(_fsRoot));
  });
}

void _testWith(FutureOr<FileSystem> Function() open) {
  late FileSystem fs;

  setUp(() async => fs = await open());

  test('can create files', () {
    expect(fs.exists('$_fsRoot/foo.txt'), isFalse);
    expect(fs.listFiles().length, 0);

    fs.createFile('$_fsRoot/foo.txt');
    expect(fs.exists('$_fsRoot/foo.txt'), isTrue);
    expect(fs.listFiles().length, 1);
    expect(fs.listFiles().first, '$_fsRoot/foo.txt');

    fs.deleteFile('$_fsRoot/foo.txt');
    expect(fs.listFiles().length, 0);
  });

  test('can create and delete multiple files', () {
    for (var i = 1; i <= 10; i++) {
      fs.createFile('$_fsRoot/foo$i.txt');
    }

    expect(fs.listFiles().length, 10);

    for (final f in fs.listFiles()) {
      fs.deleteFile(f);
    }

    expect(fs.listFiles().length, 0);
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
