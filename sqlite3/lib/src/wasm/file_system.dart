import 'dart:typed_data';

/// A virtual file system implementation for web-based `sqlite3` databases.
abstract class FileSystem {
  void createFile(String path, {bool errorIfAlreadyExists = false});
  String createTemporaryFile();
  void deleteFile(String path);

  int sizeOfFile(String path);
  void truncateFile(String path, int length);
  int read(String path, Uint8List target, int offset);
  void write(String path, Uint8List bytes, int offset);
}

class FileSystemException implements Exception {}
