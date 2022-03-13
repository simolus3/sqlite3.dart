import 'dart:async';
import 'dart:html';
import 'dart:indexed_db';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p show url;

import '../../wasm.dart';
import 'js_interop.dart';

/// A virtual file system implementation for web-based `sqlite3` databases.
abstract class FileSystem {
  factory FileSystem.inMemory() = _InMemoryFileSystem;

  /// Creates an empty file at [path].
  ///
  /// If [errorIfAlreadyExists] is set to true, and a file already exists at
  /// [path], a [FileSystemException] is thrown.
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  });

  /// Whether a file at [path] exists.
  bool exists(String path);

  /// Creates a temporary file with a unique name.
  String createTemporaryFile();

  /// Deletes a file at [path] if it exists, throwing a [FileSystemException]
  /// otherwise.
  void deleteFile(String path);

  /// Returns the size of a file at [path] if it exists.
  ///
  /// Otherwise throws a [FileSystemException].
  int sizeOfFile(String path);

  /// Sets the size of the file at [path] to [length].
  ///
  /// If the file was smaller than [length] before, the rest is filled with
  /// zeroes.
  void truncateFile(String path, int length);

  /// Reads a chunk of the file at [path] and offset [offset] into the [target]
  /// buffer.
  ///
  /// Returns the amount of bytes read.
  int read(String path, Uint8List target, int offset);

  /// Writes a chunk from [bytes] into the file at path [path] and offset
  /// [offset].
  void write(String path, Uint8List bytes, int offset);
}

/// An exception thrown by a [FileSystem] implementation.
class FileSystemException implements Exception {
  final int errorCode;

  FileSystemException([this.errorCode = SqlError.SQLITE_ERROR]);

  @override
  String toString() {
    return 'FileSystemException($errorCode)';
  }
}

class _InMemoryFileSystem implements FileSystem {
  final Map<String, Uint8List?> _files = {};

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    if (errorIfAlreadyExists && _files.containsKey(path)) {
      throw FileSystemException();
    }
    if (errorIfNotExists && !_files.containsKey(path)) {
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
    if (!_files.containsKey(path)) {
      throw FileSystemException(SqlExtendedError.SQLITE_IOERR_DELETE_NOENT);
    }

    _files.remove(path);
  }

  @override
  int read(String path, Uint8List target, int offset) {
    final file = _files[path];
    if (file == null || file.length <= offset) return 0;

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
      final newFile = Uint8List(file.length + increasedSize)
        ..setAll(0, file)
        ..setAll(offset, bytes);

      _files[path] = newFile;
    }
  }
}

class IndexedDbFileSystem implements FileSystem {
  static const _dbName = 'sqlite3_databases';
  static const _files = 'files';

  final String _persistenceRoot;
  final Database _database;

  final _InMemoryFileSystem _memory = _InMemoryFileSystem();

  IndexedDbFileSystem._(this._persistenceRoot, this._database);

  static Future<IndexedDbFileSystem> load(String persistenceRoot) async {
    final database = await window.indexedDB!.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.target.result as Database;
        database.createObjectStore(_files);
      },
    );
    final fs = IndexedDbFileSystem._(persistenceRoot, database);

    // Load persisted files from IndexedDb
    final transaction = database.transactionStore(_files, 'readonly');
    final files = transaction.objectStore(_files);

    await for (final entry in files.openCursor(autoAdvance: true)) {
      final path = entry.primaryKey! as String;

      if (p.url.isWithin(persistenceRoot, path)) {
        final object = await entry.value as Blob?;
        if (object == null) continue;

        fs._memory._files[path] = await object.arrayBuffer();
      }
    }

    return fs;
  }

  bool _shouldPersist(String path) => p.url.isWithin(_persistenceRoot, path);

  void _writeFileAsync(String path) {
    if (_shouldPersist(path)) {
      Future.sync(() async {
        final transaction = _database.transaction(_files, 'readwrite');
        await transaction
            .objectStore(_files)
            .put(Blob(<Uint8List>[_memory._files[path] ?? Uint8List(0)]), path);
      });
    }
  }

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    final exists = _memory.exists(path);
    _memory.createFile(path, errorIfAlreadyExists: errorIfAlreadyExists);

    if (!exists) {
      // Just created, so write
      _writeFileAsync(path);
    }
  }

  @override
  String createTemporaryFile() {
    var i = 0;
    while (exists('/tmp/$i')) {
      i++;
    }

    final fileName = '/tmp/$i';
    createFile(fileName);
    return fileName;
  }

  @override
  void deleteFile(String path) {
    _memory.deleteFile(path);

    if (_shouldPersist(path)) {
      Future.sync(() async {
        final transaction = _database.transactionStore(_files, 'readwrite');
        await transaction.objectStore(_files).delete(path);
      });
    }
  }

  @override
  bool exists(String path) => _memory.exists(path);

  @override
  int read(String path, Uint8List target, int offset) {
    return _memory.read(path, target, offset);
  }

  @override
  int sizeOfFile(String path) => _memory.sizeOfFile(path);

  @override
  void truncateFile(String path, int length) {
    _memory.truncateFile(path, length);
    _writeFileAsync(path);
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    _memory.write(path, bytes, offset);
    _writeFileAsync(path);
  }
}
