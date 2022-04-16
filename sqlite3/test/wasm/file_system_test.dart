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
    fs.createFile('$_fsRoot/foo.txt');
    addTearDown(() => fs.deleteFile('$_fsRoot/foo.txt'));

    expect(fs.exists('$_fsRoot/foo.txt'), isTrue);
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
