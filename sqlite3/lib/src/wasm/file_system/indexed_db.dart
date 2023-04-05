import 'dart:async';
import 'dart:collection';
import 'dart:html';
import 'dart:indexed_db';
import 'dart:indexed_db' as idb;
import 'dart:math';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:meta/meta.dart';

import '../../constants.dart';
import '../file_system.dart';
import '../js_interop.dart';
import 'memory.dart';

/// An (asynchronous) file system implementation backed by IndexedDB.
///
/// For a synchronous variant of this that implements [FileSystem], use
/// [IndexedDbFileSystem]. It uses an in-memory cache to synchronously wrap this
/// file system (at the loss of durability guarantees).
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

  Future<void> _write(int fileId, _FileWriteRequest writes) async {
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

class IndexedDbFileSystem implements FileSystem {
  final AsynchronousIndexedDbFileSystem _asynchronous;

  var _isClosing = false;
  _IndexedDbWorkItem? _currentWorkItem;

  // A cache so that synchronous changes are visible right away
  final InMemoryFileSystem _memory;
  final LinkedList<_IndexedDbWorkItem> _pendingWork = LinkedList();

  final Set<String> _inMemoryOnlyFiles = {};
  final Map<String, int> _knownFileIds = {};

  IndexedDbFileSystem._(String dbName)
      : _asynchronous = AsynchronousIndexedDbFileSystem(dbName),
        _memory = InMemoryFileSystem();

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
    if (work.insertInto(_pendingWork)) {
      _startWorkingIfNeeded();
      return work.completer.future;
    } else {
      // This item determined that it doesn't need to do any work at its place
      // in the queue, so just skip it.
      return Future.value();
    }
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

      _memory.fileData[name] = await _asynchronous.readFully(fileId);
    }
  }

  /// Waits for all pending operations to finish, then completes the future.
  ///
  /// Each call to [flush] will await pending operations made _before_ the call.
  /// Operations started after this [flush] call will not be awaited by the
  /// returned future.
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

    final previousContent = _memory.fileData[path] ?? Uint8List(0);

    _memory.write(path, bytes, offset);

    if (!_inMemoryOnlyFiles.contains(path)) {
      _submitWork(_WriteFileWorkItem(this, path, previousContent)
        ..writes.add(_OffsetAndBuffer(offset, bytes)));
    }
  }
}

abstract class _IndexedDbWorkItem extends LinkedListEntry<_IndexedDbWorkItem> {
  final Completer<void> completer = Completer.sync();

  /// Insert this item into the [pending] list, returning whether the item was
  /// actually added.
  ///
  /// Some items may want to look at the current state of the work queue for
  /// optimization purposes. For instance:
  ///
  ///  - if two writes to the same file are scheduled, they can be merged into
  ///    a single transaction for efficiency.
  ///  - if a file creation or writes are followed by inserting a delete request
  ///    to the same file, previous items can be deleted from the queue.
  bool insertInto(LinkedList<_IndexedDbWorkItem> pending) {
    pending.add(this);
    return true;
  }

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
  bool insertInto(LinkedList<_IndexedDbWorkItem> pending) {
    if (pending.isNotEmpty) {
      // Check queue from back to front and see if this delete can be merged
      // into an existing operation or if it cancels out a creation operation
      // that is pending.
      _IndexedDbWorkItem? current = pending.last;

      while (current != null) {
        if (current is _DeleteFileWorkItem) {
          // If there already is a pending "delete" request available, we don't
          // have to run a new one.
          if (current.path == path) {
            // File is already getting deleted, no need to do that again.
            return false;
          } else {
            // Unrelated delete request, look further
            current = current.previous;
          }
        } else if (current is _WriteFileWorkItem) {
          final previous = current.previous;
          if (current.path == path) {
            // There's a pending write to a file that we're deleting now, that
            // can be unscheduled now.
            current.unlink();
          }

          current = previous;
        } else if (current is _CreateFileWorkItem) {
          if (current.path == path) {
            // The creation of this file is pending. Since we're now enqueuing
            // its deletion, those two just cancel each other out.
            current.unlink();
            return false;
          }

          current = current.previous;
        } else {
          // Can't simplify further, we don't know what this general item is
          // doing.
          break;
        }
      }
    }

    pending.add(this);
    return true;
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
  bool insertInto(LinkedList<_IndexedDbWorkItem> pending) {
    var current = pending.isEmpty ? null : pending.last;

    while (current != null) {
      if (current is _WriteFileWorkItem) {
        if (current.path == path) {
          // Merge the two pending writes into one transaction.
          current.writes.addAll(writes);
          return false;
        } else {
          current = current.previous;
        }
      } else if (current is _CreateFileWorkItem) {
        if (current.path == path) {
          // Don't look further than the item that created this file, who knows
          // what happened before that.
          break;
        }

        current = current.previous;
      } else {
        break;
      }
    }

    pending.add(this);
    return true;
  }

  @override
  Future<void> run() async {
    final request = _FileWriteRequest(originalContent);

    for (final write in writes) {
      request.addWrite(write.offset, write.buffer);
    }

    await fileSystem._asynchronous
        ._write(await fileSystem._fileId(path), request);
  }
}
