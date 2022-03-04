import 'dart:math';
import 'dart:typed_data';

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
    final file = _files[path];
    if (file == null) {
      throw FileSystemException();
    }
    return file.length;
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
