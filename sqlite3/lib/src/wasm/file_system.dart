import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A virtual file system implementation for web-based `sqlite3` databases.
abstract class FileSystem {
  factory FileSystem.inMemory() = _InMemoryFileSystem;

  void createFile(String path, {bool errorIfAlreadyExists = false});
  bool exists(String path);
  String createTemporaryFile();
  void deleteFile(String path);

  int sizeOfFile(String path);
  void truncateFile(String path, int length);
  int read(String path, Uint8List target, int offset);
  void write(String path, Uint8List bytes, int offset);
}

@internal
extension LogFileSystems on FileSystem {
  /// A wrapping file system that [print]s requests and responses.
  FileSystem get logOperations => _LoggingFileSystem(this);
}

class FileSystemException implements Exception {}

class _InMemoryFileSystem implements FileSystem {
  final Map<String, Uint8List?> _files = {};

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  void createFile(String path, {bool errorIfAlreadyExists = false}) {
    if (errorIfAlreadyExists && _files.containsKey(path)) {
      throw FileSystemException();
    }

    _files.putIfAbsent(path, () => null);
  }

  @override
  String createTemporaryFile() {
    var i = 0;
    while (_files.containsKey('/tmp/$i')) {
      i++;
    }

    final fileName = '/tmp/$i';
    createFile(fileName);
    return fileName;
  }

  @override
  void deleteFile(String path) {
    _files.remove(path);
  }

  @override
  int read(String path, Uint8List target, int offset) {
    final file = _files[path];
    if (file == null) return 0;

    final available = min(target.length, file.length - offset);
    target.setRange(0, available, file, offset);
    return available;
  }

  @override
  int sizeOfFile(String path) {
    if (!_files.containsKey(path)) throw FileSystemException();

    return _files[path]?.length ?? 0;
  }

  @override
  void truncateFile(String path, int length) {
    final file = _files[path];

    final result = Uint8List(length);
    if (file != null) {
      result.setRange(0, min(length, file.length), file);
    }

    _files[path] = result;
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    final file = _files[path] ?? Uint8List(0);
    final increasedSize = offset + bytes.length - file.length;

    if (increasedSize <= 0) {
      // Can write directy
      file.setRange(offset, offset + bytes.length, bytes);
    } else {
      // We need to grow the file first
      _files[path] = Uint8List(file.length + increasedSize)
        ..setAll(0, file)
        ..setAll(offset, bytes);
    }
  }
}

class _LoggingFileSystem implements FileSystem {
  final FileSystem _inner;

  _LoggingFileSystem(this._inner);

  T _logFn<T>(T Function() inner) {
    try {
      final result = inner();
      print(' <= $result');
      return result;
    } on Object catch (e) {
      print(' <=! $e');
      rethrow;
    }
  }

  @override
  void createFile(String path, {bool errorIfAlreadyExists = false}) {
    print('createFile($path, errorIfAlreadyExists: $errorIfAlreadyExists)');
    return _logFn(() =>
        _inner.createFile(path, errorIfAlreadyExists: errorIfAlreadyExists));
  }

  @override
  String createTemporaryFile() {
    print('createTemporaryFile()');
    return _logFn(() => _inner.createTemporaryFile());
  }

  @override
  void deleteFile(String path) {
    print('deleteFile($path)');
    return _logFn(() => _inner.deleteFile(path));
  }

  @override
  bool exists(String path) {
    print('exists($path)');
    return _logFn(() => _inner.exists(path));
  }

  @override
  int read(String path, Uint8List target, int offset) {
    print('read($path, ${target.length} bytes, $offset)');
    return _logFn(() => _inner.read(path, target, offset));
  }

  @override
  int sizeOfFile(String path) {
    print('sizeOfFile($path)');
    return _logFn(() => _inner.sizeOfFile(path));
  }

  @override
  void truncateFile(String path, int length) {
    print('truncateFile($path, $length)');
    return _logFn(() => _inner.truncateFile(path, length));
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    print('write($path, ${bytes.length} bytes, $offset)');
    return _logFn(() => _inner.write(path, bytes, offset));
  }
}
