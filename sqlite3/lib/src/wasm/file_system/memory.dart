import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../constants.dart';
import '../file_system.dart';

@internal
class InMemoryFileSystem implements FileSystem {
  final Map<String, Uint8List?> fileData = {};

  @override
  bool exists(String path) => fileData.containsKey(path);

  @override
  List<String> get files => fileData.keys.toList(growable: false);

  @override
  void clear() => fileData.clear();

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    final fileExists = exists(path);
    if (errorIfAlreadyExists && fileExists) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File already exists');
    }
    if (errorIfNotExists && !fileExists) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File not exists');
    }

    fileData.putIfAbsent(path, () => null);
    if (!fileExists) {
      _log('Add file: $path');
    }
  }

  @override
  String createTemporaryFile() {
    var i = 0;
    while (fileData.containsKey('/tmp/$i')) {
      i++;
    }
    final fileName = '/tmp/$i';
    createFile(fileName);
    return fileName;
  }

  @override
  void deleteFile(String path) {
    if (!fileData.containsKey(path)) {
      throw FileSystemException(SqlExtendedError.SQLITE_IOERR_DELETE_NOENT);
    }
    _log('Delete file: $path');
    fileData.remove(path);
  }

  @override
  int read(String path, Uint8List target, int offset) {
    final file = fileData[path];
    if (file == null || file.length <= offset) return 0;

    final available = min(target.length, file.length - offset);
    target.setRange(0, available, file, offset);
    return available;
  }

  @override
  int sizeOfFile(String path) {
    if (!fileData.containsKey(path)) throw FileSystemException();

    return fileData[path]?.length ?? 0;
  }

  @override
  void truncateFile(String path, int length) {
    final file = fileData[path];

    final result = Uint8List(length);
    if (file != null) {
      result.setRange(0, min(length, file.length), file);
    }

    fileData[path] = result;
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    final file = fileData[path] ?? Uint8List(0);
    final increasedSize = offset + bytes.length - file.length;

    if (increasedSize <= 0) {
      // Can write directy
      file.setRange(offset, offset + bytes.length, bytes);
    } else {
      // We need to grow the file first
      final newFile = Uint8List(file.length + increasedSize)
        ..setAll(0, file)
        ..setAll(offset, bytes);

      fileData[path] = newFile;
    }
  }

  void _log(String message) {
    if (debugFileSystem) {
      print('VFS: $message');
    }
  }
}
