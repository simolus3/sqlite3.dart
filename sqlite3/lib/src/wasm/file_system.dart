import 'dart:async';
import 'dart:html';
import 'dart:indexed_db';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:mutex/mutex.dart';
import 'package:path/path.dart' as p show url, posix;

import '../../wasm.dart';
import 'js_interop.dart';

/// A virtual file system implementation for web-based `sqlite3` databases.
abstract class FileSystem {
  /// Creates an in-memory file system that deletes data when the tab is
  /// closed.
  factory FileSystem.inMemory({int blockSize = 32, bool debugLog = false}) =>
      _InMemoryFileSystem(null, blockSize, debugLog);

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
  List<String> get files;

  /// Deletes all file
  Future<void> clear();

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

class _InMemoryFileSystem implements FileSystem {
  final Map<String, List<Uint8List>> _files = {};
  final IndexedDbFileSystem? _persistent;
  final int _blockSize;
  final bool _debugLog;

  _InMemoryFileSystem(this._persistent, this._blockSize, this._debugLog);

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  List<String> get files => _files.keys.toList(growable: false);

  @override
  Future<void> clear() async => _files.clear();

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    final _exists = exists(path);
    if (errorIfAlreadyExists && _exists) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File already exists');
    }
    if (errorIfNotExists && !_exists) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File not exists');
    }

    _files.putIfAbsent(path, () => []);
    if (!_exists) {
      _log('Add file: $path');
      unawaitedSafe(_persistent?._persistFile(path, newFile: true));
    }
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
    _log('Delete file: $path');
    _files.remove(path);
    unawaitedSafe(_persistent?._deleteFileFromDb(path));
  }

  @override
  int read(String path, Uint8List target, int offset) {
    final file = _files[path];
    if (file == null) {
      throw FileSystemException(
          SqlExtendedError.SQLITE_IOERR_READ, 'File not exists');
    }

    final fileLength = _calculateSize(file);
    final available = min(target.length, fileLength - offset);
    if (available == 0 || fileLength <= offset) {
      return 0;
    }

    int? firstBlock;
    int? lastBlock;
    for (var i = 0; i < available; i++) {
      final position = offset + i;
      final blockId = position ~/ _blockSize;
      final byteId = position - blockId * _blockSize;
      target[i] = file[blockId][byteId];
      firstBlock ??= blockId;
      lastBlock = blockId;
    }

    _log('Read [${available}b from ${lastBlock! - firstBlock! + 1} blocks '
        '@ #$firstBlock-$lastBlock] $path');
    return available;
  }

  int _calculateSize(List<Uint8List> file) {
    return file.fold(0, (v, e) => v + e.length);
  }

  @override
  int sizeOfFile(String path) {
    final file = _files[path];
    if (file == null) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File not exists');
    } else {
      return _calculateSize(file);
    }
  }

  @override
  void truncateFile(String path, int newSize) {
    final file = _files[path];
    if (file == null) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'File not exists');
    }

    if (newSize < 0) {
      throw FileSystemException(
          SqlError.SQLITE_IOERR, 'newLength must be >= 0');
    }

    final oldBlockCount = file.length;
    final fileSize = _calculateSize(file);
    if (fileSize == newSize) {
      // Skip if size not changes
      return;
    }

    if (fileSize < newSize) {
      // Expand by simply write zeros
      final diff = newSize - fileSize;
      write(path, Uint8List(diff), fileSize);
      return;
    }

    int? modifiedIndex;
    if (newSize == 0) {
      file.clear();
    } else if (fileSize > newSize) {
      // Shrink
      var diff = fileSize - newSize;
      while (diff > 0) {
        final block = file.lastOrNull!;
        final remove = min(diff, block.length);

        if (remove == block.length) {
          // Remove whole blocks
          file.removeLast();
          diff -= remove;
          continue;
        }

        // Shrink block
        final newBlock = Uint8List(block.length - remove);
        newBlock.setRange(0, newBlock.length, block);
        modifiedIndex = file.length - 1;
        file[modifiedIndex] = newBlock;
        break;
      }
    }

    // Collect modified blocks
    final blocks = modifiedIndex != null
        ? [Uint8List.fromList(file[modifiedIndex])]
        : <Uint8List>[];

    final diff = file.length - oldBlockCount;
    final modifiedSize = newSize - fileSize;
    final modified = blocks.firstOrNull?.length ?? 0;

    _log('Truncate '
        '[${modifiedSize >= 0 ? '+${modifiedSize}b' : '${modifiedSize}b'}'
        ', ${diff >= 0 ? '+$diff block' : '$diff block'}'
        '${modified > 0 ? ', modified: ${modified}b in 1 block' : ''}] '
        '$path');

    unawaitedSafe(_persistent?._persistFile(path,
        modifiedBlocks: blocks,
        newBlockCount: file.length,
        offset: modifiedIndex));
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    final file = _files[path];
    if (file == null) {
      throw FileSystemException(
          SqlExtendedError.SQLITE_IOERR_WRITE, 'File not exists');
    }
    if (bytes.isEmpty) {
      return;
    }

    final blockCount = file.length;
    final fileSize = _calculateSize(file);
    final end = bytes.length + offset;

    // Expand file
    if (fileSize < end) {
      var remain = end - fileSize;
      while (remain > 0) {
        final block = file.lastOrNull;
        final add = min(remain, _blockSize);
        final newBlock = Uint8List(add);
        if (block != null && block.length < _blockSize) {
          // Expand a partial block
          newBlock.setRange(0, block.length, block);
          file[file.length - 1] = newBlock;
          remain -= add - block.length;
        } else {
          // Expand whole blocks
          file.add(newBlock);
          remain -= add;
        }
      }
    }

    // Write blocks
    int? firstBlock;
    int? lastBlock;
    for (var i = 0; i < bytes.length; i++) {
      final position = offset + i;
      final blockId = position ~/ _blockSize;
      final byteId = position - blockId * _blockSize;
      file[blockId][byteId] = bytes[i];
      firstBlock ??= blockId;
      lastBlock = blockId;
    }

    // Get modified blocks
    final blocks = file
        .getRange(firstBlock!, lastBlock! + 1)
        .map((e) => Uint8List.fromList(e))
        .toList();

    final diff = file.length - blockCount;
    _log('Write [${bytes.length}b in ${blocks.length} block'
        '${diff > 0 ? ' (+$diff block)' : ''} @ '
        '#$firstBlock-${firstBlock + blocks.length - 1}] '
        '$path');

    unawaitedSafe(_persistent?._persistFile(path,
        modifiedBlocks: blocks,
        newBlockCount: file.length,
        offset: firstBlock));
  }

  void unawaitedSafe(Future<void>? body) {
    unawaited(Future.sync(() async {
      try {
        await body;
      } on Exception catch (e, s) {
        print(e);
        print(s);
      }
    }));
  }

  void _log(String message) {
    if (_debugLog) {
      print('VFS[${_persistent?.dbName ?? 'in-memory'}] $message');
    }
  }
}

/// A file system storing files divided into blocks in an IndexedDB database.
///
/// As sqlite3's file system is synchronous and IndexedDB isn't, no guarantees
/// on durability can be made. Instead, file changes are written at some point
/// after the database is changed. However you can wait for changes manually
/// with [flush]
///
/// In the future, we may want to store individual blocks instead.

class IndexedDbFileSystem implements FileSystem {
  Database? _database;
  final String dbName;

  late final _InMemoryFileSystem _memory;
  final ReadWriteMutex _mutex = ReadWriteMutex();

  static final _instances = <String>{};

  IndexedDbFileSystem._(this.dbName, int blockSize, bool debugLog) {
    _memory = _InMemoryFileSystem(this, blockSize, debugLog);
  }

  /// Loads an IndexedDB file system that will consider files in
  /// [dbName] database.
  ///
  /// When one application needs to support different database files, putting
  /// them into different folders and setting the persistence root to ensure
  /// that one [IndexedDbFileSystem] will only see one of them decreases memory
  /// usage.
  ///
  ///
  /// With [dbName] you can set IndexedDB database name
  static Future<IndexedDbFileSystem> init({
    required String dbName,
    int blockSize = 32,
    bool debugLog = false,
  }) async {
    if (_instances.contains(dbName)) {
      throw FileSystemException(0, "A '$dbName' database already opened");
    }
    _instances.add(dbName);
    final fs = IndexedDbFileSystem._(dbName, blockSize, debugLog);
    await fs._sync();
    return fs;
  }

  Future<void> _openDatabase(
      {String? addFile, List<String>? deleteFiles}) async {
    //
    void onUpgrade(VersionChangeEvent event) {
      final database = event.target.result as Database;
      if (addFile != null) {
        database.createObjectStore(addFile);
      }
      if (deleteFiles != null) {
        for (final file in deleteFiles) {
          database.deleteObjectStore(file);
        }
      }
    }

    int? version;
    void Function(VersionChangeEvent)? onUpgradeNeeded;
    if (addFile != null || deleteFiles != null) {
      version = (_database!.version ?? 1) + 1;
      onUpgradeNeeded = onUpgrade;
    }

    _database?.close();
    _database = await self.indexedDB!
        .open(dbName, version: version, onUpgradeNeeded: onUpgradeNeeded)
        // A bug in Dart SDK can cause deadlock here. Timeout added as workaround
        // https://github.com/dart-lang/sdk/issues/48854
        .timeout(const Duration(milliseconds: 30000),
            onTimeout: () => throw FileSystemException(
                0, "Failed to open database. Database blocked"));
  }

  /// Returns all IndexedDB database names accessible from the current context.
  ///
  /// This may return `null` if `IDBFactory.databases()` is not supported by the
  /// current browser.
  static Future<List<String>?> databases() async {
    return (await self.indexedDB!.databases())?.map((e) => e.name).toList();
  }

  static Future<void> deleteDatabase(
      [String dbName = 'sqlite3_databases']) async {
    // A bug in Dart SDK can cause deadlock here. Timeout added as workaround
    // https://github.com/dart-lang/sdk/issues/48854
    await self.indexedDB!.deleteDatabase(dbName).timeout(
        const Duration(milliseconds: 1000),
        onTimeout: () => throw FileSystemException(
            0, "Failed to delete database. Database is still open"));
  }

  bool get isClosed => _database == null;

  Future<void> close() async {
    await protectWrite(() async {
      if (_database != null) {
        _memory._log('Close database');
        await _memory.clear();
        _database!.close();
        _database = null;
        _instances.remove(dbName);
      }
    });
  }

  void _checkClosed() {
    if (_database == null) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'FileSystem closed');
    }
  }

  Future<void> protectWrite(Future<void> Function() criticalSection) async {
    await _mutex.acquireWrite();
    try {
      return await criticalSection();
    } on Exception catch (e, s) {
      print(e);
      print(s);
      rethrow;
    } finally {
      _mutex.release();
    }
  }

  Future<T> completed<T>(Request req) {
    final completer = Completer<T>();

    req.onSuccess.first.then((_) {
      completer.complete(req.result as T);
    });

    req.onError.first.then((e) {
      completer.completeError(e);
    });

    return completer.future;
  }

  Future<void> _sync() async {
    Future<List<Uint8List>> readFile(String fileName) async {
      final transaction = _database!.transactionStore(fileName, 'readonly');
      final store = transaction.objectStore(fileName);

      final keys = await completed<List<dynamic>>(store.getAllKeys(null));
      if (keys.isEmpty) {
        return [];
      }
      if (keys.cast<int>().max != keys.length - 1) {
        throw Exception('File integrity exception');
      }

      final blocks = await completed<List<dynamic>>(store.getAll(null));
      if (blocks.length != keys.length) {
        throw Exception('File integrity exception');
      }

      return Future.wait(blocks.cast<Blob>().map((b) => b.arrayBuffer()));
    }

    await protectWrite(() async {
      _memory._log('Open database (block size: ${_memory._blockSize})');
      await _memory.clear();
      await _openDatabase();

      for (final path in _database!.objectStoreNames!) {
        try {
          final file = await readFile(path);
          if (file.isNotEmpty) {
            _memory._files[path] = file;
            _memory._log(
                '-- loaded: $path [${_memory.sizeOfFile(path) ~/ 1024}KB]');
          } else {
            _memory._log('-- skipped: $path (empty file)');
          }
        } on Exception catch (e) {
          _memory._log('-- failed: $path');
          print(e);
        }
      }
    });
  }

  String _normalize(String path) {
    if (path.endsWith('/') || path.endsWith('.')) {
      throw FileSystemException(
          SqlExtendedError.SQLITE_CANTOPEN_ISDIR, 'Path is a directory');
    }
    return p.posix.normalize('/${path}');
  }

  Future<void> flush() async {
    _checkClosed();
    await _mutex.acquireWrite();
    _mutex.release();
  }

  Future<void> _clearStore(String path) async {
    await protectWrite(() async {
      final transaction = _database!.transaction(path, 'readwrite');
      try {
        final store = transaction.objectStore(path);
        await store.clear();
        transaction.commit();
      } on Exception catch (_) {
        transaction.abort();
        rethrow;
      }
    });
  }

  Future<void> _persistFile(
    String path, {
    List<Uint8List> modifiedBlocks = const [],
    int newBlockCount = 0,
    int? offset,
    bool newFile = false,
  }) async {
    Future<void> writeFile() async {
      final transaction = _database!.transaction(path, 'readwrite');
      final store = transaction.objectStore(path);
      try {
        final currentBlockCount = await store.count();

        if (currentBlockCount > newBlockCount) {
          for (var i = currentBlockCount - 1; i >= newBlockCount; i--) {
            await store.delete(i);
          }
        }
        if (offset != null) {
          for (var i = 0; i < modifiedBlocks.length; i++) {
            final value = Blob(<Uint8List>[modifiedBlocks[i]]);
            store.putRequestUnsafe(value, offset + i);
          }
        }
        transaction.commit();
      } on Exception catch (_) {
        transaction.abort();
        rethrow;
      }
    }

    Future<void> addFile() async {
      if (!_database!.objectStoreNames!.contains(path)) {
        await _openDatabase(addFile: path);
      }
    }

    await protectWrite(() async {
      if (newFile) {
        await addFile();
      } else {
        await writeFile();
      }
    });
  }

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.createFile(
      _path,
      errorIfAlreadyExists: errorIfAlreadyExists,
      errorIfNotExists: errorIfNotExists,
    );
  }

  @override
  String createTemporaryFile() {
    _checkClosed();
    final path = _memory.createTemporaryFile();
    return path;
  }

  @override
  void deleteFile(String path) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.deleteFile(_path);
  }

  Future<void> _deleteFileFromDb(String path) async {
    // Soft delete
    await _clearStore(path);
  }

  @override
  Future<void> clear() async {
    _checkClosed();
    await protectWrite(() async {
      final _files = _memory.files;
      await _memory.clear();
      await _openDatabase(deleteFiles: _files);
    });
  }

  @override
  bool exists(String path) {
    _checkClosed();
    final _path = _normalize(path);
    return _memory.exists(_path);
  }

  @override
  List<String> get files {
    _checkClosed();
    return _memory.files;
  }

  @override
  int read(String path, Uint8List target, int offset) {
    _checkClosed();
    final _path = _normalize(path);
    return _memory.read(_path, target, offset);
  }

  @override
  int sizeOfFile(String path) {
    _checkClosed();
    final _path = _normalize(path);
    return _memory.sizeOfFile(_path);
  }

  @override
  void truncateFile(String path, int length) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.truncateFile(_path, length);
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.write(_path, bytes, offset);
  }
}
