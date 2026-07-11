@JS()
library;

import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sqlite3/src/wasm/async.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:web/web.dart' as web;

import '../../constants.dart';
import '../../vfs.dart';
import '../js_interop.dart';
import '../../in_memory_vfs.dart';
import '../../utils.dart';

// Format of the files store: `{name: <path>, length: <size>}`. See also
// [_FileEntry], which is the actual object that we're storing in the
// database.
const _filesStore = 'files';
const _fileName = 'name';
const _fileNameIndex = 'fileName';

// Format of blocks store: Key is a (file id, offset) pair, value is a blob.
// Each blob is 4096 bytes large. If we have a file that isn't a multiple of
// this length, we set the "length" attribute on the file instead of storing
// shorter blobs. This simplifies the implementation.
const _blocksStore = 'blocks';
final _storesJs = [_filesStore.toJS, _blocksStore.toJS].toJS;

const _blockSize = 4096;
const _maxFileSize = 9007199254740992;

/// An (asynchronous) file system implementation backed by IndexedDB.
///
/// For a synchronous variant of this that implements [FileSystem], use
/// [IndexedDbFileSystem]. It uses an in-memory cache to synchronously wrap this
/// file system (at the loss of durability guarantees).
@internal
class AsynchronousIndexedDbFileSystem {
  web.IDBDatabase? _database;
  final String _dbName;

  AsynchronousIndexedDbFileSystem(this._dbName);

  @visibleForTesting
  web.IDBDatabase? get database => _database;

  bool get _isClosed => _database == null;

  Future<void> open() async {
    // We need to wrap the open call in a completer. Otherwise the `open()`
    // future never completes if we're blocked.
    final completer = Completer<web.IDBDatabase>.sync();
    final openRequest = indexedDB!.open(_dbName, 1);
    openRequest.onupgradeneeded = (web.IDBVersionChangeEvent change) {
      final database = openRequest.result as web.IDBDatabase;
      if (change.oldVersion == 0) {
        final files = database.createObjectStore(
          _filesStore,
          web.IDBObjectStoreParameters(autoIncrement: true),
        );
        files.createIndex(
          _fileNameIndex,
          _fileName.toJS,
          web.IDBIndexParameters(unique: true),
        );

        database.createObjectStore(_blocksStore);
      }
    }.toJS;

    final openFuture = openRequest.completeOrBlocked<web.IDBDatabase>();
    completer.complete(openFuture);
    _database = await completer.future;
  }

  void close() {
    _database?.close();
    _database = null;
  }

  Future<void> _runTransaction(
    Future<void> Function(_IndexedDbTransaction) body, {
    required String mode,
  }) async {
    final raw = _database!.transaction(_storesJs, mode);
    final tx = _IndexedDbTransaction(raw);
    await runWithNativeMicrotasks(() async {
      try {
        await body(tx);
      } on Object {
        raw.abort();
        rethrow;
      }
      raw.commit();
    });

    await tx._completer.future;
    if (tx.closeAfterwards) {
      close();
    }
  }

  Future<void> _performWrites(List<_IndexedDbWorkItem> items) {
    return _runTransaction(mode: 'readwrite', (tx) async {
      for (final item in items) {
        await item.run(tx);
      }
    });
  }
}

final class _IndexedDbTransaction {
  final web.IDBTransaction _transaction;
  final Completer<void> _completer = Completer.sync();
  var closeAfterwards = false;

  final web.IDBObjectStore _files, _blocks;

  _IndexedDbTransaction(this._transaction)
    : _files = _transaction.objectStore(_filesStore),
      _blocks = _transaction.objectStore(_blocksStore) {
    final handleComplete = () {
      _completer.complete();
    }.toJS;

    _transaction.oncomplete = handleComplete;
    _transaction.onabort = handleComplete;
    _transaction.onerror = () {
      _completer.completeError(
        _transaction.error ?? web.DOMException('IDB transaction error'),
      );
    }.toJS;
  }

  void _checkNotClosed() {
    if (_completer.isCompleted) {
      throw StateError('IDB transaction already completed');
    }
  }

  web.IDBKeyRange _rangeOverFile(
    int fileId, {
    int startOffset = 0,
    int endOffsetInclusive = _maxFileSize,
  }) {
    // The key of blocks is an array, [fileId, offset]. So if we want to iterate
    // through a fixed file, we use `[fileId, 0]` as a lower and `[fileId, max]`
    // as a higher bound.
    return web.IDBKeyRange.bound(
      [fileId.toJS, startOffset.toJS].toJS,
      [fileId.toJS, endOffsetInclusive.toJS].toJS,
    );
  }

  Future<void> clear() {
    _checkNotClosed();

    return (_files.clear().complete(), _blocks.clear().complete()).wait;
  }

  /// Loads all file paths and their ids.
  Future<Map<String, int>> listFiles() async {
    final result = <String, int>{};

    final iterator = _files
        .index(_fileNameIndex)
        .openKeyCursor()
        .cursorIterator();

    while (await iterator.moveNext()) {
      final row = iterator.current;

      result[(row.key! as JSString).toDart] =
          (row.primaryKey! as JSNumber).toDartInt;
    }
    return result;
  }

  Future<int?> fileIdForPath(String path) async {
    final index = _files.index(_fileNameIndex);

    return (await index.getKey(path.toJS).complete<JSNumber>()).toDartInt;
  }

  Future<_FileEntry> _readFile(int fileId) {
    return _files.get(fileId.toJS).complete<_FileEntry?>().then((value) {
      if (value == null) {
        throw ArgumentError.value(
          fileId,
          'fileId',
          'File not found in database',
        );
      } else {
        return value;
      }
    });
  }

  /// Starts reading all blocks for a file.
  ///
  /// In older versions of this package, we stored binary data as [web.Blob]
  /// instances that can only be read asynchronously. We can't await that read
  /// while we have an IndexedDB transaction though, as yielding can invalidate
  /// the transaction. These reads are put into [additionalReads] and must be
  /// awaited after the transaction.
  Future<Uint8Buffer> startRead(
    int fileId,
    List<Future<void>> additionalReads,
  ) async {
    final file = await _readFile(fileId);
    final result = Uint8Buffer(file.length);

    final reader = _blocks
        .openCursor(_rangeOverFile(fileId))
        .cursorIterator<web.IDBCursorWithValue>();
    while (await reader.moveNext()) {
      final row = reader.current;
      final key = (row.key as JSArray).toDart;
      final rowOffset = (key[1] as JSNumber).toDartInt;
      if (rowOffset >= file.length) {
        // In older versions of this implementation, we sometimes generated
        // trailing blocks. We'll just ignore them here to avoid crashing, these
        // don't cause any damage otherwise.
        break;
      }
      final length = min(_blockSize, file.length - rowOffset);

      void completeRead(ByteBuffer data) {
        result.setAll(rowOffset, data.asUint8List(0, length));
      }

      if (row.value.instanceOfString('Blob')) {
        // We can't have an async suspension in here because that would close
        // the transaction. Launch the reader now and wait for all reads later.
        additionalReads.add(
          (row.value as web.Blob).byteBuffer().then(completeRead),
        );
      } else {
        completeRead((row.value as JSArrayBuffer).toDart);
      }
    }

    return result;
  }

  Future<int> createFile(String path) async {
    _checkNotClosed();

    final res = await _files
        .put(_FileEntry(name: path, length: 0))
        .complete<JSNumber>();
    return res.toDartInt;
  }

  Future<void> write(int fileId, _FileWriteRequest writes) async {
    _checkNotClosed();

    final file = await _readFile(fileId);

    Future<void> writeBlock(int blockStart, Uint8List block) async {
      assert(block.length == _blockSize, 'Invalid block size');

      // Check if we're overriding (parts of) an existing block
      final cursor = await _blocks
          .openCursor(web.IDBKeyRange.only([fileId.toJS, blockStart.toJS].toJS))
          .complete<web.IDBCursorWithValue?>();

      final value = block.buffer.toJS;

      if (cursor == null) {
        // There isn't, let's write a new block
        await _blocks
            .put(value, [fileId.toJS, blockStart.toJS].toJS)
            .complete<JSAny?>();
      } else {
        await cursor.update(value).complete<JSAny?>();
      }
    }

    final changedOffsets = writes.replacedBlocks.keys.toList()..sort();
    await Future.wait(
      changedOffsets.map(
        (offset) => writeBlock(offset, writes.replacedBlocks[offset]!),
      ),
    );

    if (writes.newFileLength != file.length) {
      final fileCursor = _files.openCursor(fileId.toJS).cursorIterator();
      await fileCursor.moveNext();
      // Update the file length as recorded in the database
      await fileCursor.current
          .update(_FileEntry(name: file.name, length: writes.newFileLength))
          .complete();
    }
  }

  Future<void> truncate(int fileId, int length) async {
    _checkNotClosed();

    // First, let's find the size of the file
    final file = await _readFile(fileId);
    final fileLength = file.length;

    if (fileLength > length) {
      final endOffset = (length ~/ _blockSize) * _blockSize;

      // Delete all higher blocks (those starting at or past the end offset).
      await _blocks
          .delete(_rangeOverFile(fileId, startOffset: endOffset))
          .complete();
    } else if (fileLength < length) {
      // We don't need to do anything here, missing blocks count as zero bytes.
    }

    // Update the file length as recorded in the database
    final fileCursor = _files.openCursor(fileId.toJS).cursorIterator();
    await fileCursor.moveNext();

    await fileCursor.current
        .update(_FileEntry(name: file.name, length: length))
        .complete();
  }

  Future<void> deleteFile(int id) async {
    _checkNotClosed();

    final blocksRange = _rangeOverFile(
      id,
      startOffset: 0,
      endOffsetInclusive: _maxFileSize,
    );
    await Future.wait<void>([
      _blocks.delete(blocksRange).complete(),
      _files.delete(id.toJS).complete(),
    ]);
  }
}

/// An object that we store in IndexedDB to keep track of files.
///
/// Using a `@JS` is easier than dealing with JavaScript objects exported as
/// maps.
@JS()
extension type _FileEntry._(JSObject _) implements JSObject {
  external String get name;
  external int get length;

  external factory _FileEntry({required String name, required int length});
}

class _FileWriteRequest {
  final Uint8List originalContent;
  final Map<int, Uint8List> replacedBlocks = {};
  int newFileLength;

  _FileWriteRequest(this.originalContent)
    : newFileLength = originalContent.length;

  void _updateBlock(int blockOffset, int offsetInBlock, Uint8List data) {
    final block = replacedBlocks.putIfAbsent(blockOffset, () {
      final block = Uint8List(_blockSize);

      if (originalContent.length > blockOffset) {
        block.setAll(
          0,
          originalContent.buffer.asUint8List(
            originalContent.offsetInBytes + blockOffset,
            min(_blockSize, originalContent.length - blockOffset),
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
      final blockStart = offsetInFile ~/ _blockSize * _blockSize;

      int offsetInBlock, bytesToWrite;

      if (offsetInFile % _blockSize != 0) {
        // Write to block boundary
        offsetInBlock = offsetInFile % _blockSize;
        bytesToWrite = min(
          _blockSize - offsetInBlock,
          data.length - offsetInData,
        );
      } else {
        // Write full block if possible
        bytesToWrite = min(_blockSize, data.length - offsetInData);
        offsetInBlock = 0;
      }

      final chunk = data.buffer.asUint8List(
        data.offsetInBytes + offsetInData,
        bytesToWrite,
      );
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
/// with [flush].
///
/// {@category wasm}
final class IndexedDbFileSystem extends BaseVirtualFileSystem {
  final AsynchronousIndexedDbFileSystem _asynchronous;

  var _isClosing = false;
  var _isWorking = false;

  bool _writeAutomatically = true;

  // A cache so that synchronous changes are visible right away
  final InMemoryFileSystem _memory;
  final LinkedList<_IndexedDbWorkItem> _pendingWork = LinkedList();

  final Set<String> _inMemoryOnlyFiles = {};
  final Map<String, int> _knownFileIds = {};

  IndexedDbFileSystem._(
    String dbName, {
    String vfsName = 'indexeddb',
    super.random,
  }) : _asynchronous = AsynchronousIndexedDbFileSystem(dbName),
       _memory = InMemoryFileSystem(random: random),
       super(name: vfsName);

  /// Loads an IndexedDB file system identified by the [dbName].
  ///
  /// Each file system with a different name will store an independent file
  /// system.
  ///
  /// The [writeAutomatically] parameter controls how writes are persisted in
  /// IndexedDB. When enabled (the default), writes are asynchronously written
  /// to IndexedDB without any durability guarantees. You can invoke [flush] to
  /// force a transaction, though.
  /// When disabled, no IndexedDB writes are scheduled by default. Instead, all
  /// writes are batched up until [flush] is called explicitly. This allows
  /// being more explicit about when to write to IndexedDB.
  static Future<IndexedDbFileSystem> open({
    required String dbName,
    String vfsName = 'indexeddb',
    Random? random,
    bool writeAutomatically = true,
  }) async {
    final fs = IndexedDbFileSystem._(dbName, vfsName: vfsName, random: random);
    fs._writeAutomatically = writeAutomatically;
    await fs._asynchronous.open();
    await fs._readFiles();
    return fs;
  }

  /// Returns all IndexedDB database names accessible from the current context.
  ///
  /// This may return `null` if `IDBFactory.databases()` is not supported by the
  /// current browser.
  static Future<List<String>?> databases() async {
    return (await indexedDB!.databases().toDart).toDart
        .map((e) => e.name)
        .toList();
  }

  /// Deletes an IndexedDB database.
  static Future<void> deleteDatabase([
    String dbName = 'sqlite3_databases',
  ]) async {
    // A bug in Dart SDK can cause deadlock here. Timeout added as workaround
    // https://github.com/dart-lang/sdk/issues/48854
    await indexedDB!
        .deleteDatabase(dbName)
        .completeOrBlocked()
        .timeout(
          const Duration(milliseconds: 1000),
          onTimeout: () => throw VfsException(1),
        );
  }

  /// Whether this file system is closing or closed.
  ///
  /// To await a full close operation, call and await [close].
  bool get isClosed => _isClosing || _asynchronous._isClosed;

  Future<void> _submitWork(_IndexedDbWorkItem work) {
    _checkClosed();

    // See if this unit of work can be combined with scheduled work units.
    if (work.insertInto(_pendingWork)) {
      _startWorkingIfNeeded(isImplicit: true);
      return work.completer.future;
    } else {
      // This item determined that it doesn't need to do any work at its place
      // in the queue, so just skip it.
      return Future.value();
    }
  }

  Future<void> _submitWorkFunction(
    Future<void> Function(_IndexedDbTransaction) work,
    String description,
  ) {
    return _submitWork(_FunctionWorkItem(work, description));
  }

  Future<void> _startWorkingIfNeeded({required bool isImplicit}) async {
    if (isImplicit && !_writeAutomatically) return;

    if (!_isWorking && _pendingWork.isNotEmpty) {
      _isWorking = true;
      final items = _pendingWork.toList();
      _pendingWork.clear();

      await _asynchronous._performWrites(items).whenComplete(() {
        _isWorking = false;

        for (final item in items) {
          item.completer.complete();
        }

        // In case there's another item in the waiting list
        _startWorkingIfNeeded(isImplicit: isImplicit);
      });
    }
  }

  Future<void> close() async {
    if (!_isClosing) {
      final result = _submitWorkFunction((tx) async {
        tx.closeAfterwards = true;
      }, 'close');
      _isClosing = true;
      _startWorkingIfNeeded(isImplicit: false);
      return result;
    } else if (_pendingWork.isNotEmpty) {
      // Already closing, await all pending operations then.
      final op = _pendingWork.last;
      return op.completer.future;
    }
  }

  void _checkClosed() {
    if (isClosed) {
      throw VfsException(SqlError.SQLITE_IOERR);
    }
  }

  Future<int> _fileId(_IndexedDbTransaction tx, String path) async {
    if (_knownFileIds.containsKey(path)) {
      return _knownFileIds[path]!;
    } else {
      return _knownFileIds[path] = (await tx.fileIdForPath(path))!;
    }
  }

  Future<void> _readFiles() async {
    final additionalReads = <Future<void>>[];

    await _asynchronous._runTransaction(mode: 'readonly', (tx) async {
      final rawFiles = await tx.listFiles();
      _knownFileIds.addAll(rawFiles);

      for (final entry in rawFiles.entries) {
        final name = entry.key;
        final fileId = entry.value;

        final data = await tx.startRead(fileId, additionalReads);
        _memory.fileData[name] = data;
      }
    });
    await additionalReads.wait;
  }

  /// Waits for all pending operations to finish, then completes the future.
  ///
  /// Each call to [flush] will await pending operations made _before_ the call.
  /// Operations started after this [flush] call will not be awaited by the
  /// returned future.
  Future<void> flush() {
    return _startWorkingIfNeeded(isImplicit: false);
  }

  @override
  int xAccess(String path, int flags) => _memory.xAccess(path, flags);

  @override
  void xDelete(String path, int syncDir) {
    _memory.xDelete(path, syncDir);

    if (!_inMemoryOnlyFiles.remove(path)) {
      _submitWork(_DeleteFileWorkItem(this, path));
    }
  }

  @override
  String xFullPathName(String path) => _memory.xFullPathName(path);

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final pathStr = path.path ?? random.randomFileName(prefix: '/');
    final existedBefore = _memory.xAccess(pathStr, 0) != 0;

    final inMemoryFile = _memory.xOpen(Sqlite3Filename(pathStr), flags);
    final deleteOnClose = (flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE) != 0;

    if (!existedBefore) {
      if (deleteOnClose) {
        // No point in persisting this file, it doesn't exist and won't exist
        // after we're done.
        _inMemoryOnlyFiles.add(pathStr);
      } else {
        _submitWork(_CreateFileWorkItem(this, pathStr));
      }
    }

    return (
      outFlags: 0,
      file: _IndexedDbFile(this, inMemoryFile.file, pathStr),
    );
  }

  @override
  void xSleep(Duration duration) {
    // noop
  }
}

class _IndexedDbFile implements VirtualFileSystemFileV1 {
  final IndexedDbFileSystem vfs;
  final VirtualFileSystemFile memoryFile;
  final String path;

  _IndexedDbFile(this.vfs, this.memoryFile, this.path);

  @override
  void xRead(Uint8List target, int fileOffset) {
    memoryFile.xRead(target, fileOffset);
  }

  @override
  int get xDeviceCharacteristics => 0;

  @override
  int get xSectorSize => 4096;

  @override
  int xCheckReservedLock() => memoryFile.xCheckReservedLock();

  @override
  void xClose() {}

  @override
  int xFileSize() => memoryFile.xFileSize();

  @override
  void xLock(int mode) => memoryFile.xLock(mode);

  @override
  void xSync(int flags) {
    // We can't wait for a sync either way, so this just has to be a noop
  }

  @override
  int xFileControl(int op, int ptr) {
    return SqlError.SQLITE_NOTFOUND;
  }

  @override
  void xTruncate(int size) {
    vfs._checkClosed();
    memoryFile.xTruncate(size);

    if (!vfs._inMemoryOnlyFiles.contains(path)) {
      vfs._submitWorkFunction(
        (tx) async => tx.truncate(await vfs._fileId(tx, path), size),
        'truncate $path',
      );
    }
  }

  @override
  void xUnlock(int mode) => memoryFile.xUnlock(mode);

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    vfs._checkClosed();

    if (vfs._inMemoryOnlyFiles.contains(path)) {
      // There's nothing to persist, so we just forward the write to the in-
      // memory buffer.
      memoryFile.xWrite(buffer, fileOffset);
      return;
    }

    final previousContent = vfs._memory.fileData[path] ?? Uint8Buffer();
    final previousList = previousContent.buffer.asUint8List(
      0,
      previousContent.length,
    );
    memoryFile.xWrite(buffer, fileOffset);

    // We need to copy the buffer for the write because it will become invalid
    // after this synchronous method returns.
    final copy = Uint8List(buffer.length)..setAll(0, buffer);

    vfs._submitWork(
      _WriteFileWorkItem(vfs, path, previousList)
        ..writes.add(_OffsetAndBuffer(fileOffset, copy)),
    );
  }
}

sealed class _IndexedDbWorkItem extends LinkedListEntry<_IndexedDbWorkItem> {
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

  Future<void> run(_IndexedDbTransaction tx);
}

final class _FunctionWorkItem extends _IndexedDbWorkItem {
  final Future<void> Function(_IndexedDbTransaction) work;
  final String description;

  _FunctionWorkItem(this.work, this.description);

  @override
  Future<void> run(_IndexedDbTransaction tx) => work(tx);
}

final class _DeleteFileWorkItem extends _IndexedDbWorkItem {
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
  Future<void> run(_IndexedDbTransaction tx) async {
    final id = await fileSystem._fileId(tx, path);
    fileSystem._knownFileIds.remove(path);
    await tx.deleteFile(id);
  }
}

final class _CreateFileWorkItem extends _IndexedDbWorkItem {
  final IndexedDbFileSystem fileSystem;
  final String path;

  _CreateFileWorkItem(this.fileSystem, this.path);

  @override
  Future<void> run(_IndexedDbTransaction tx) async {
    final id = await tx.createFile(path);
    fileSystem._knownFileIds[path] = id;
  }
}

final class _WriteFileWorkItem extends _IndexedDbWorkItem {
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
  Future<void> run(_IndexedDbTransaction tx) async {
    final request = _FileWriteRequest(originalContent);

    for (final write in writes) {
      request.addWrite(write.offset, write.buffer);
    }

    await tx.write(await fileSystem._fileId(tx, path), request);
  }
}
