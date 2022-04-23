import 'dart:async';
import 'dart:html';
import 'dart:indexed_db';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../wasm.dart';
import 'js_interop.dart';

part 'file_system_v2.dart';

/// A virtual file system implementation for web-based `sqlite3` databases.
abstract class FileSystem {
  /// Creates an in-memory file system that deletes data when the tab is
  /// closed.
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

  /// Lists all files stored in this file system.
  @Deprecated('Use files() instead')
  List<String> listFiles();

  /// Lists all files stored in this file system.
  List<String> files();

  /// Deletes all file
  FutureOr<void> clear();

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
  final String message;

  FileSystemException(
      [this.errorCode = SqlError.SQLITE_ERROR, this.message = 'SQLITE_ERROR']);

  @override
  String toString() {
    return 'FileSystemException: ($errorCode) $message';
  }
}

/// An exception thrown by a [FileSystem] implementation when try to access file
/// outside of persistence root
class FileSystemAccessException extends FileSystemException {
  FileSystemAccessException()
      : super(SqlExtendedError.SQLITE_IOERR_ACCESS,
            'Path is not within persistence root');
}

class _InMemoryFileSystem implements FileSystem {
  final Map<String, Uint8List?> _files = {};

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  @Deprecated('Use files() instead')
  List<String> listFiles() => files();

  @override
  List<String> files() => _files.keys.toList(growable: false);

  @override
  void clear() => _files.clear();

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    if (errorIfAlreadyExists && _files.containsKey(path)) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File already exists');
    }
    if (errorIfNotExists && !_files.containsKey(path)) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File not exists');
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
    if (!_files.containsKey(path)) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File not exists');
    }

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

/// A file system storing whole files in an IndexedDB database.
///
/// As sqlite3's file system is synchronous and IndexedDB isn't, no guarantees
/// on durability can be made. Instead, file changes are written at some point
/// after the database is changed.
///
/// In the future, we may want to store individual blocks instead.

class IndexedDbFileSystem implements FileSystem {
  static const _dbName = 'sqlite3_databases';
  static const _files = 'files';

  final String _persistenceRoot;
  final Database _database;

  final _InMemoryFileSystem _memory = _InMemoryFileSystem();

  IndexedDbFileSystem._(this._persistenceRoot, this._database);

  /// Loads an IndexedDB file system that will consider files in
  /// [persistenceRoot].
  ///
  /// When one application needs to support different database files, putting
  /// them into different folders and setting the persistence root to ensure
  /// that one [IndexedDbFileSystem] will only see one of them decreases memory
  /// usage.
  ///
  /// The persistence root can be set to `/` to make all files available.
  /// Be careful not to use the same or nested [persistenceRoot] for
  /// different instances. These can overwrite each other and undefined behavior
  /// can occur.
  ///
  /// IndexedDbFileSystem doesn't prepend [persistenceRoot] to filenames.
  /// Rather works more like a guard. If you create/delete file you must prefix
  /// the path with [persistenceRoot], otherwise saving to IndexedDD will fail
  /// silently.
  @Deprecated('Use IndexedDbFileSystemV2 instead')
  static Future<IndexedDbFileSystem> load(String persistenceRoot) async {
    // Not using window.indexedDB because we want to support workers too.
    final database = await self.indexedDB!.open(
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

  bool _shouldPersist(String path) =>
      path.startsWith('/tmp/') || p.url.isWithin(_persistenceRoot, path);

  void _canPersist(String path) {
    if (!_shouldPersist(path)) {
      throw FileSystemAccessException();
    }
  }

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
    _canPersist(path);
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
    _canPersist(path);
    _memory.deleteFile(path);

    if (_shouldPersist(path)) {
      Future.sync(() async {
        final transaction = _database.transactionStore(_files, 'readwrite');
        await transaction.objectStore(_files).delete(path);
      });
    }
  }

  /// Deletes all file
  @override
  void clear() {
    final dbFiles = files();
    _memory.clear();
    Future.sync(() async {
      final transaction = _database.transactionStore(_files, 'readwrite');
      for (final file in dbFiles) {
        await transaction.objectStore(_files).delete(file);
      }
    });
  }

  @override
  bool exists(String path) {
    _canPersist(path);
    return _memory.exists(path);
  }

  @override
  List<String> listFiles() => files();

  @override
  List<String> files() => _memory.files();

  @override
  int read(String path, Uint8List target, int offset) {
    _canPersist(path);
    return _memory.read(path, target, offset);
  }

  @override
  int sizeOfFile(String path) {
    _canPersist(path);
    return _memory.sizeOfFile(path);
  }

  @override
  void truncateFile(String path, int length) {
    _canPersist(path);
    _memory.truncateFile(path, length);
    _writeFileAsync(path);
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    _canPersist(path);
    _memory.write(path, bytes, offset);
    _writeFileAsync(path);
  }
}
