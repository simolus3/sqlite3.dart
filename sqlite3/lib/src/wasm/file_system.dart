import 'dart:async';
import 'dart:collection';
import 'dart:html';
import 'dart:indexed_db';
import 'dart:indexed_db' as idb;
import 'dart:math';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:meta/meta.dart';

import '../../wasm.dart';
import 'js_interop.dart';

const _debugFileSystem =
    bool.fromEnvironment('sqlite3.wasm.fs.debug', defaultValue: false);

/// A virtual file system implementation for web-based `sqlite3` databases.
abstract class FileSystem {
  /// Creates an in-memory file system that deletes data when the tab is
  /// closed.
  factory FileSystem.inMemory() => _InMemoryFileSystem();

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

  /// Deletes all files stored in this file system.
  void clear();

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

abstract class PersistentStorage {
  Future<void> flush();
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
  final Map<String, Uint8List?> _files = {};

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  List<String> get files => _files.keys.toList(growable: false);

  @override
  void clear() => _files.clear();

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

    _files.putIfAbsent(path, () => null);
    if (!_exists) {
      _log('Add file: $path');
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

  void _log(String message) {
    if (_debugFileSystem) {
      print('VFS: $message');
    }
  }
}

/// An (asynchronous) file system implementation backed by IndexedDB.
///
/// For a synchronous variant of this that implements [FileSystem], use
/// [IndexedDbFileSystem]. It uses an in-memory cache to synchronously wrap this
/// file system (at the loss of durability).
@internal
class AsynchronousIndexedDbFileSystem {
  // Format of the files store: `{name: <path>, length: <size>}`. See also
  // [_FileEntry], which is the actual object that we're storing in the
  // database.
  static const _filesStore = 'files';
  static const _fileName = 'name';
  static const _fileNameIndex = 'fileName';

  // Format of blocks store: Key is a (file id, offset) pair, value is a blob.
  // Each blob is 4096 bytes large. If we have a file that isn't a multiple of
  // this length, we set the "length" attribute on the file instead of storing
  // shorter blobs. This simplifies the implementation.
  static const _blocksStore = 'blocks';

  static const _stores = [_filesStore, _blocksStore];

  static const _blockSize = 4096;
  static const _maxFileSize = 9007199254740992;

  Database? _database;
  final String _dbName;

  AsynchronousIndexedDbFileSystem(this._dbName);

  bool get _isClosed => _database == null;

  KeyRange _rangeOverFile(int fileId,
      {int startOffset = 0, int endOffsetInclusive = _maxFileSize}) {
    // The key of blocks is an array, [fileId, offset]. So if we want to iterate
    // through a fixed file, we use `[fileId, 0]` as a lower and `[fileId, max]`
    // as a higher bound.
    return keyRangeBound([fileId, startOffset], [fileId, endOffsetInclusive]);
  }

  Future<void> open() async {
    // We need to wrap the open call in a completer. Otherwise the `open()`
    // future never completes if we're blocked.
    final completer = Completer<Database>.sync();
    final openFuture = self.indexedDB!.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (change) {
        final database = change.target.result as Database;

        if (change.oldVersion == null || change.oldVersion == 0) {
          final files =
              database.createObjectStore(_filesStore, autoIncrement: true);
          files.createIndex(_fileNameIndex, _fileName, unique: true);

          database.createObjectStore(_blocksStore);
        }
      },
      onBlocked: (e) => completer.completeError('Opening database blocked: $e'),
    );
    completer.complete(openFuture);

    _database = await completer.future;
  }

  void close() {
    _database?.close();
  }

  Future<void> clear() {
    final transaction = _database!.transactionList(_stores, 'readwrite');

    return Future.wait<void>([
      for (final name in _stores) transaction.objectStore(name).clear(),
    ]);
  }

  /// Loads all file paths and their ids.
  Future<Map<String, int>> listFiles() async {
    final transaction = _database!.transactionStore(_filesStore, 'readonly');
    final result = <String, int>{};

    final iterator = transaction
        .objectStore(_filesStore)
        .index(_fileNameIndex)
        .openKeyCursorNative()
        .cursorIterator();

    while (await iterator.moveNext()) {
      final row = iterator.current;

      result[row.key! as String] = row.primaryKey! as int;
    }
    return result;
  }

  Future<int?> fileIdForPath(String path) async {
    final transaction = _database!.transactionStore(_filesStore, 'readonly');
    final index = transaction.objectStore(_filesStore).index(_fileNameIndex);

    return await index.getKey(path) as int?;
  }

  Future<int> createFile(String path) {
    final transaction = _database!.transactionStore(_filesStore, 'readwrite');
    final store = transaction.objectStore(_filesStore);

    return store
        .putRequestUnsafe(_FileEntry(name: path, length: 0))
        .completed<int>();
  }

  Future<_FileEntry> _readFile(Transaction transaction, int fileId) {
    final files = transaction.objectStore(_filesStore);
    return files
        .getValue(fileId)
        // Not converting to Dart because _FileEntry is an anonymous JS class,
        // we don't want the object to be turned into a map.
        .completed<_FileEntry?>(convertResultToDart: false)
        .then((value) {
      if (value == null) {
        throw ArgumentError.value(
            fileId, 'fileId', 'File not found in database');
      } else {
        return value;
      }
    });
  }

  Future<Uint8List> readFully(int fileId) async {
    final transaction = _database!.transactionList(_stores, 'readonly');
    final blocks = transaction.objectStore(_blocksStore);

    final file = await _readFile(transaction, fileId);
    final result = Uint8List(file.length);

    final readOperations = <Future<void>>[];

    final reader = blocks
        .openCursorNative(_rangeOverFile(fileId))
        .cursorIterator<CursorWithValue>();
    while (await reader.moveNext()) {
      final row = reader.current;
      final rowOffset = (row.key! as List)[1] as int;
      final length = min(_blockSize, file.length - rowOffset);

      // We can't have an async suspension in here because that would close the
      // transaction. Launch the reader now and wait for all reads later.
      readOperations.add(Future.sync(() async {
        final data = await (row.value as Blob).arrayBuffer();
        result.setAll(rowOffset, data.buffer.asUint8List(0, length));
      }));
    }
    await Future.wait(readOperations);

    return result;
  }

  Future<int> read(int fileId, int offset, Uint8List target) async {
    final transaction = _database!.transactionList(_stores, 'readonly');
    final blocks = transaction.objectStore(_blocksStore);

    final file = await _readFile(transaction, fileId);

    final previousBlockStart = (offset ~/ _blockSize) * _blockSize;
    final range = _rangeOverFile(fileId, startOffset: previousBlockStart);
    var bytesRead = 0;

    final readOperations = <Future<void>>[];

    final iterator =
        blocks.openCursorNative(range).cursorIterator<CursorWithValue>();
    while (await iterator.moveNext()) {
      final row = iterator.current;

      final rowOffset = (row.key! as List)[1] as int;
      final blob = row.value as Blob;
      final dataLength = min(blob.size, file.length - rowOffset);

      if (rowOffset < offset) {
        // This block starts before the section that we're interested in, so cut
        // off the initial bytes.
        final startInRow = offset - rowOffset;
        final lengthToCopy = min(dataLength, target.length);
        bytesRead += lengthToCopy;

        // Do the reading async because we loose the transaction on the first
        // suspension.
        readOperations.add(Future.sync(() async {
          final data = await blob.arrayBuffer();

          target.setRange(
            0,
            lengthToCopy,
            data.buffer
                .asUint8List(data.offsetInBytes + startInRow, lengthToCopy),
          );
        }));

        if (lengthToCopy >= target.length) {
          break;
        }
      } else {
        final startInTarget = rowOffset - offset;
        final lengthToCopy = min(dataLength, target.length - startInTarget);
        if (lengthToCopy < 0) {
          // This row starts past the end of the section we're interested in.
          break;
        }

        bytesRead += lengthToCopy;
        readOperations.add(Future.sync(() async {
          final data = await blob.arrayBuffer();

          target.setAll(startInTarget,
              data.buffer.asUint8List(data.offsetInBytes, lengthToCopy));
        }));

        if (lengthToCopy >= target.length - startInTarget) {
          break;
        }
      }
    }

    await Future.wait(readOperations);
    return bytesRead;
  }

  Future<void> write(int fileId, _FileWriteRequest writes) async {
    final transaction = _database!.transactionList(_stores, 'readwrite');
    final blocks = transaction.objectStore(_blocksStore);
    final file = await _readFile(transaction, fileId);

    Future<void> writeBlock(int blockStart, Uint8List block) async {
      assert(block.length == _blockSize, 'Invalid block size');

      // Check if we're overriding (parts of) an existing block
      final cursor = await blocks
          .openCursorNative(keyRangeOnly([fileId, blockStart]))
          .completed<idb.CursorWithValue?>();
      final blob = Blob(<Uint8List>[block]);

      if (cursor == null) {
        // There isn't, let's write a new block
        await blocks.put(blob, [fileId, blockStart]);
      } else {
        await cursor.update(blob);
      }
    }

    final changedOffsets = writes.replacedBlocks.keys.toList()..sort();
    await Future.wait(changedOffsets
        .map((offset) => writeBlock(offset, writes.replacedBlocks[offset]!)));

    if (writes.newFileLength != file.length) {
      final files = transaction.objectStore(_filesStore);
      final fileCursor = await files.openCursor(key: fileId).first;
      // Update the file length as recorded in the database
      await fileCursor
          .update(_FileEntry(name: file.name, length: writes.newFileLength));
    }
  }

  Future<void> truncate(int fileId, int length) async {
    final transaction = _database!.transactionList(_stores, 'readwrite');
    final files = transaction.objectStore(_filesStore);
    final blocks = transaction.objectStore(_blocksStore);

    // First, let's find the size of the file
    final file = await _readFile(transaction, fileId);
    final fileLength = file.length;

    if (fileLength > length) {
      final lastBlock = (length ~/ _blockSize) * _blockSize;

      // Delete all higher blocks
      await blocks.delete(_rangeOverFile(fileId, startOffset: lastBlock + 1));
    } else if (fileLength < length) {}

    // Update the file length as recorded in the database
    final fileCursor = await files.openCursor(key: fileId).first;

    await fileCursor.update(_FileEntry(name: file.name, length: length));
  }

  Future<void> deleteFile(int id) async {
    final transaction = _database!
        .transactionList(const [_filesStore, _blocksStore], 'readwrite');

    final blocksRange = keyRangeBound([id, 0], [id, _maxFileSize]);
    await Future.wait<void>([
      transaction.objectStore(_blocksStore).delete(blocksRange),
      transaction.objectStore(_filesStore).delete(id),
    ]);
  }
}

/// An object that we store in IndexedDB to keep track of files.
///
/// Using a `@JS` is easier than dealing with JavaScript objects exported as
/// maps.
@JS()
@anonymous
class _FileEntry {
  external String get name;
  external int get length;

  external factory _FileEntry({required String name, required int length});
}

class _FileWriteRequest {
  static const _blockLength = AsynchronousIndexedDbFileSystem._blockSize;

  final Uint8List originalContent;
  final Map<int, Uint8List> replacedBlocks = {};
  int newFileLength;

  _FileWriteRequest(this.originalContent)
      : newFileLength = originalContent.length;

  void _updateBlock(int blockOffset, int offsetInBlock, Uint8List data) {
    final block = replacedBlocks.putIfAbsent(blockOffset, () {
      final block = Uint8List(_blockLength);

      if (originalContent.length > blockOffset) {
        block.setAll(
          0,
          originalContent.buffer.asUint8List(
            originalContent.offsetInBytes + blockOffset,
            min(_blockLength, originalContent.length - blockOffset),
          ),
        );
      }

      return block;
    });

    block.setAll(offsetInBlock, data);
  }

  void addWrite(int offset, Uint8List data) {
    var offsetInData = 0;
    while (offsetInData < data.length) {
      final offsetInFile = offset + offsetInData;
      final blockStart = offsetInFile ~/ _blockLength * _blockLength;

      int offsetInBlock, bytesToWrite;

      if (offsetInFile % _blockLength != 0) {
        // Write to block boundary
        offsetInBlock = offsetInFile % _blockLength;
        bytesToWrite =
            min(_blockLength - offsetInBlock, data.length - offsetInData);
      } else {
        // Write full block if possible
        bytesToWrite = min(_blockLength, data.length - offsetInData);
        offsetInBlock = 0;
      }

      final chunk = data.buffer
          .asUint8List(data.offsetInBytes + offsetInData, bytesToWrite);
      offsetInData += bytesToWrite;

      _updateBlock(blockStart, offsetInBlock, chunk);
    }

    newFileLength = max(newFileLength, offset + data.length);
  }
}

class _OffsetAndBuffer {
  final int offset;
  final Uint8List buffer;

  _OffsetAndBuffer(this.offset, this.buffer);
}

/// A file system storing files divided into blocks in an IndexedDB database.
///
/// As sqlite3's file system is synchronous and IndexedDB isn't, no guarantees
/// on durability can be made. Instead, file changes are written at some point
/// after the database is changed. However you can wait for changes manually
/// with [flush]
///
/// In the future, we may want to store individual blocks instead.

class IndexedDbFileSystem implements FileSystem, PersistentStorage {
  final AsynchronousIndexedDbFileSystem _asynchronous;

  var _isClosing = false;
  _IndexedDbWorkItem? _currentWorkItem;

  // A cache so that synchronous changes are visible right away
  final _InMemoryFileSystem _memory;
  final LinkedList<_IndexedDbWorkItem> _pendingWork = LinkedList();

  final Set<String> _inMemoryOnlyFiles = {};
  final Map<String, int> _knownFileIds = {};

  IndexedDbFileSystem._(String dbName)
      : _asynchronous = AsynchronousIndexedDbFileSystem(dbName),
        _memory = _InMemoryFileSystem();

  /// Loads an IndexedDB file system identified by the [dbName].
  ///
  /// Each file system with a different name will store an independent file
  /// system.
  static Future<IndexedDbFileSystem> open({required String dbName}) async {
    final fs = IndexedDbFileSystem._(dbName);
    await fs._asynchronous.open();
    await fs._readFiles();
    return fs;
  }

  /// Returns all IndexedDB database names accessible from the current context.
  ///
  /// This may return `null` if `IDBFactory.databases()` is not supported by the
  /// current browser.
  static Future<List<String>?> databases() async {
    return (await self.indexedDB!.databases())?.map((e) => e.name).toList();
  }

  /// Deletes an IndexedDB database.
  static Future<void> deleteDatabase(
      [String dbName = 'sqlite3_databases']) async {
    // A bug in Dart SDK can cause deadlock here. Timeout added as workaround
    // https://github.com/dart-lang/sdk/issues/48854
    await self.indexedDB!.deleteDatabase(dbName).timeout(
        const Duration(milliseconds: 1000),
        onTimeout: () => throw FileSystemException(
            0, "Failed to delete database. Database is still open"));
  }

  /// Whether this file system is closing or closed.
  ///
  /// To await a full close operation, call and await [close].
  bool get isClosed => _isClosing || _asynchronous._isClosed;

  Future<void> _submitWork(_IndexedDbWorkItem work) {
    _checkClosed();

    // See if this unit of work can be combined with scheduled work units.
    if (_pendingWork.isNotEmpty) {
      _IndexedDbWorkItem? compareWith = _pendingWork.last;
      assert(_currentWorkItem != compareWith,
          'Current work item should be removed from queue');

      while (compareWith != null) {
        final result = work.mergeWith(compareWith);
        switch (result) {
          case _WorkSimplicationResult.mergedInto:
            return compareWith.completer.future;
          case _WorkSimplicationResult.cannotSimplify:
            compareWith = null;
            break;
          case _WorkSimplicationResult.lookFurther:
            compareWith = compareWith.previous;
            break;
          case _WorkSimplicationResult.deletePreviousAndContinue:
          case _WorkSimplicationResult.deletePreviousAndMergedWith:
            final next = compareWith.previous;
            compareWith.unlink();
            compareWith = next;

            if (result == _WorkSimplicationResult.deletePreviousAndMergedWith) {
              return next?.completer.future ?? Future.value();
            }
        }
      }
    }

    _pendingWork.add(work);
    _startWorkingIfNeeded();

    return work.completer.future;
  }

  Future<void> _submitWorkFunction(
      FutureOr<void> Function() work, String description) {
    return _submitWork(_FunctionWorkItem(work, description));
  }

  void _startWorkingIfNeeded() {
    if (_currentWorkItem == null && _pendingWork.isNotEmpty) {
      final item = _currentWorkItem = _pendingWork.first;
      _pendingWork.remove(item);

      final workUnit = Future(item.run).whenComplete(() {
        _currentWorkItem = null;

        // In case there's another item in the waiting list
        _startWorkingIfNeeded();
      });
      item.completer.complete(workUnit);
    }
  }

  Future<void> close() async {
    if (!_isClosing) {
      final result = _submitWorkFunction(_asynchronous.close, 'close');
      _isClosing = true;
      return result;
    } else if (_pendingWork.isNotEmpty) {
      // Already closing, await all pending operations then.
      final op = _pendingWork.last;
      return op.completer.future;
    }
  }

  void _checkClosed() {
    if (isClosed) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'FileSystem closed');
    }
  }

  Future<int> _fileId(String path) async {
    if (_knownFileIds.containsKey(path)) {
      return _knownFileIds[path]!;
    } else {
      return _knownFileIds[path] = (await _asynchronous.fileIdForPath(path))!;
    }
  }

  Future<void> _readFiles() async {
    final rawFiles = await _asynchronous.listFiles();
    _knownFileIds.addAll(rawFiles);

    for (final entry in rawFiles.entries) {
      final name = entry.key;
      final fileId = entry.value;

      _memory._files[name] = await _asynchronous.readFully(fileId);
    }
  }

  /// Waits for all pending operations to finish, then completes the future.
  ///
  /// Each call to [flush] will await pending operations made _before_ the call.
  /// Operations started after this [flush] call will not be awaited by the
  /// returned future.
  @override
  Future<void> flush() {
    return _submitWorkFunction(() {}, 'flush');
  }

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    _checkClosed();
    final existsBefore = _memory.exists(path);
    _memory.createFile(
      path,
      errorIfAlreadyExists: errorIfAlreadyExists,
      errorIfNotExists: errorIfNotExists,
    );

    if (!existsBefore) {
      _submitWork(_CreateFileWorkItem(this, path));
    }
  }

  @override
  String createTemporaryFile() {
    _checkClosed();
    final path = _memory.createTemporaryFile();
    _inMemoryOnlyFiles.add(path);
    return path;
  }

  @override
  void deleteFile(String path) {
    _memory.deleteFile(path);

    if (!_inMemoryOnlyFiles.remove(path)) {
      _submitWork(_DeleteFileWorkItem(this, path));
    }
  }

  @override
  Future<void> clear() async {
    _memory.clear();
    await _submitWorkFunction(_asynchronous.clear, 'clear');
  }

  @override
  bool exists(String path) {
    _checkClosed();
    return _memory.exists(path);
  }

  @override
  List<String> get files {
    _checkClosed();
    return _memory.files;
  }

  @override
  int read(String path, Uint8List target, int offset) {
    _checkClosed();
    return _memory.read(path, target, offset);
  }

  @override
  int sizeOfFile(String path) {
    _checkClosed();
    return _memory.sizeOfFile(path);
  }

  @override
  void truncateFile(String path, int length) {
    _checkClosed();
    _memory.truncateFile(path, length);

    if (!_inMemoryOnlyFiles.contains(path)) {
      _submitWorkFunction(
          () async => _asynchronous.truncate(await _fileId(path), length),
          'truncate $path');
    }
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    _checkClosed();

    final previousContent = _memory._files[path] ?? Uint8List(0);

    _memory.write(path, bytes, offset);

    if (!_inMemoryOnlyFiles.contains(path)) {
      _submitWork(_WriteFileWorkItem(this, path, previousContent)
        ..writes.add(_OffsetAndBuffer(offset, bytes)));
    }
  }
}

enum _WorkSimplicationResult {
  cannotSimplify,
  lookFurther,
  deletePreviousAndContinue,
  deletePreviousAndMergedWith,
  mergedInto,
}

abstract class _IndexedDbWorkItem extends LinkedListEntry<_IndexedDbWorkItem> {
  final Completer<void> completer = Completer.sync();

  _WorkSimplicationResult mergeWith(_IndexedDbWorkItem other) =>
      _WorkSimplicationResult.cannotSimplify;

  FutureOr<void> run();
}

class _FunctionWorkItem extends _IndexedDbWorkItem {
  final FutureOr<void> Function() work;
  final String description;

  _FunctionWorkItem(this.work, this.description);

  @override
  FutureOr<void> run() => work();
}

class _DeleteFileWorkItem extends _IndexedDbWorkItem {
  final IndexedDbFileSystem fileSystem;
  final String path;

  _DeleteFileWorkItem(this.fileSystem, this.path);

  @override
  _WorkSimplicationResult mergeWith(_IndexedDbWorkItem other) {
    if (other is _DeleteFileWorkItem) {
      // If there already is a pending "delete" request available, we don't have
      // to run a new one.
      return other.path == path
          ? _WorkSimplicationResult.mergedInto
          : _WorkSimplicationResult.lookFurther;
    } else if (other is _WriteFileWorkItem) {
      return other.path == path
          ? _WorkSimplicationResult.deletePreviousAndContinue
          : _WorkSimplicationResult.lookFurther;
    } else if (other is _CreateFileWorkItem) {
      return other.path == path
          ? _WorkSimplicationResult.deletePreviousAndMergedWith
          : _WorkSimplicationResult.lookFurther;
    }

    return _WorkSimplicationResult.cannotSimplify;
  }

  @override
  Future<void> run() async {
    final id = await fileSystem._fileId(path);
    fileSystem._knownFileIds.remove(path);
    await fileSystem._asynchronous.deleteFile(id);
  }
}

class _CreateFileWorkItem extends _IndexedDbWorkItem {
  final IndexedDbFileSystem fileSystem;
  final String path;

  _CreateFileWorkItem(this.fileSystem, this.path);

  @override
  Future<void> run() async {
    final id = await fileSystem._asynchronous.createFile(path);
    fileSystem._knownFileIds[path] = id;
  }
}

class _WriteFileWorkItem extends _IndexedDbWorkItem {
  final IndexedDbFileSystem fileSystem;
  final String path;

  final Uint8List originalContent;
  final List<_OffsetAndBuffer> writes = [];

  _WriteFileWorkItem(this.fileSystem, this.path, this.originalContent);

  @override
  _WorkSimplicationResult mergeWith(_IndexedDbWorkItem other) {
    if (other is _WriteFileWorkItem) {
      if (other.path == path) {
        other.writes.addAll(writes);
        return _WorkSimplicationResult.mergedInto;
      } else {
        return _WorkSimplicationResult.lookFurther;
      }
    } else if (other is _CreateFileWorkItem) {
      return other.path == path
          ? _WorkSimplicationResult.cannotSimplify
          : _WorkSimplicationResult.lookFurther;
    }

    return _WorkSimplicationResult.cannotSimplify;
  }

  @override
  Future<void> run() async {
    final request = _FileWriteRequest(originalContent);

    for (final write in writes) {
      request.addWrite(write.offset, write.buffer);
    }

    await fileSystem._asynchronous
        .write(await fileSystem._fileId(path), request);
  }
}
