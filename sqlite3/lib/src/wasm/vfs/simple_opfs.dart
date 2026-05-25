import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:web/web.dart'
    show
        FileSystemDirectoryHandle,
        FileSystemSyncAccessHandle,
        FileSystemReadWriteOptions,
        FileSystemRemoveOptions,
        DOMException;

import '../../constants.dart';
import '../../vfs.dart';
import '../js_interop.dart';
import '../../in_memory_vfs.dart';
import '../../platform/web.dart';

@internal
enum FileType {
  database('/database'),
  journal('/database-journal');

  final String filePath;

  const FileType(this.filePath);

  static final byName = {for (final entry in values) entry.filePath: entry};
}

/// A [VirtualFileSystem] for the `sqlite3` wasm library based on the [file system access API].
///
/// By design, this file system can only store two files: `/database` and
/// `/database-journal`. Thus, when this file system is used, the only sqlite3
/// database that will be persisted properly is the one at `/database`.
///
/// The limitation of only being able to store two files comes from the fact
/// that we can't synchronously _open_ files in with the file system access API,
/// only reads and writes are synchronous.
/// By having a known amount of files to store, we can open both files (done in
/// [SimpleOpfsFileSystem.inDirectory] or [SimpleOpfsFileSystem.loadFromStorage]),
/// which is asynchronous too. The actual file system work, which needs to be
/// synchronous for sqlite3 to function, does not need any further wrapper.
///
/// Please note that [SimpleOpfsFileSystem]s are only available in dedicated web workers,
/// not in the JavaScript context for a tab or a shared web worker.
///
/// [file system access API]: https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API
///
/// {@category wasm}
final class SimpleOpfsFileSystem extends BaseVirtualFileSystem {
  // The storage idea here is to open sync file handles at the beginning, so
  // that no new async open needs to happen when these callbacks are invoked by
  // sqlite3.
  // We open a sync file for each stored file ([FileType]), plus a meta file
  // file handle that describes whether files exist or not. Handles for stored
  // files just store the raw data directly. The meta file is a 2-byte file
  // storing whether the database or the journal file exists. By storing this
  // information in a secondary file, we avoid the problem of having to query
  // the FileSystem Access API to check whether a file exists, which can only be
  // done asynchronously.

  _OpfsFiles? _files;

  /// An in-memory overlay used for files that aren't persisted (e.g. temporary
  /// materialized views).
  final InMemoryFileSystem _memory = InMemoryFileSystem();

  /// Creates an OPFS-based file system in a closed state.
  ///
  /// Before using this file system, call [open] to load the required access
  /// handles.
  SimpleOpfsFileSystem({String vfsName = 'simple-opfs'}) : super(name: vfsName);

  static Future<(FileSystemDirectoryHandle?, FileSystemDirectoryHandle)>
  _resolveDir(String path, {bool create = true}) async {
    final storage = storageManager;
    if (storage == null) {
      throw VfsException(SqlError.SQLITE_ERROR);
    }

    FileSystemDirectoryHandle? parent;
    var opfsDirectory = await storage.directory;

    for (final segment in pathComponents(path)) {
      parent = opfsDirectory;
      opfsDirectory = await opfsDirectory.getDirectory(segment, create: create);
    }

    return (parent, opfsDirectory);
  }

  /// Resolves a [FileSystemDirectoryHandle] from a path resolved against the
  /// OPFS root.
  ///
  /// The directory is created recursively if [create] is enabled (the default).
  static Future<FileSystemDirectoryHandle> resolveDirectory(
    String path, {
    bool create = true,
  }) async {
    final (_, handle) = await _resolveDir(path, create: create);
    return handle;
  }

  /// Loads an [SimpleOpfsFileSystem] in the desired [path] under the root directory
  /// for OPFS as given by `navigator.storage.getDirectory()` in JavaScript.
  ///
  /// Throws a [VfsException] if OPFS is not available - please note that
  /// this file system implementation requires a recent browser and only works
  /// in dedicated web workers.
  ///
  /// When [readWriteUnsafe] is passed, the synchronous file handles are opened
  /// using the [proposed lock mode](https://github.com/whatwg/fs/blob/main/proposals/MultipleReadersWriters.md).
  /// This mode is currently not supported across browsers, but can be used on
  /// Chrome for faster database access across tabs.
  static Future<SimpleOpfsFileSystem> loadFromStorage(
    String path, {
    String vfsName = 'simple-opfs',
    bool readWriteUnsafe = false,
  }) async {
    final storage = storageManager;
    if (storage == null) {
      throw VfsException(SqlError.SQLITE_ERROR);
    }

    final directory = await resolveDirectory(path);
    return inDirectory(
      directory,
      vfsName: vfsName,
      readWriteUnsafe: readWriteUnsafe,
    );
  }

  /// Deletes the file system directory handle that would store sqlite3
  /// databases when using [loadFromStorage] with the same path.
  static Future<void> deleteFromStorage(String path) async {
    final FileSystemDirectoryHandle? parent;
    final FileSystemDirectoryHandle handle;

    try {
      (parent, handle) = await _resolveDir(path, create: false);
      // ignore: invalid_runtime_check_with_js_interop_types
    } on JSAny catch (e) {
      // TODO: Remove type clause (needs Dart 3.12 as a minimum version)
      if (e.isA<DOMException>()) {
        final asDomException = e as DOMException;
        if (asDomException.name == 'NotFoundError' ||
            asDomException.name == 'TypeMismatchError') {
          // Directory doesn't exist, ignore.
          return;
        }
      }

      rethrow;
    }

    if (parent != null) {
      await parent
          .removeEntry(handle.name, FileSystemRemoveOptions(recursive: true))
          .toDart;
    }
  }

  /// Loads an [SimpleOpfsFileSystem] in the desired [root] directory, which must be
  /// a Dart wrapper around a [FileSystemDirectoryHandle].
  ///
  /// When [readWriteUnsafe] is passed, the synchronous file handles are opened
  /// using the [proposed lock mode](https://github.com/whatwg/fs/blob/main/proposals/MultipleReadersWriters.md).
  /// This mode is currently not supported across browsers, but can be used on
  /// Chrome for faster database access across tabs.
  ///
  /// [FileSystemDirectoryHandle]: https://developer.mozilla.org/en-US/docs/Web/API/FileSystemDirectoryHandle
  static Future<SimpleOpfsFileSystem> inDirectory(
    FileSystemDirectoryHandle root, {
    String vfsName = 'simple-opfs',
    bool readWriteUnsafe = false,
  }) async {
    final fs = SimpleOpfsFileSystem(vfsName: vfsName);
    await fs.open(root, readWriteUnsafe: readWriteUnsafe);
    return fs;
  }

  _OpfsFiles _requireFiles() {
    if (_files case final files?) {
      return files;
    }
    throw StateError('VFS closed');
  }

  FileType? _recognizeType(String path) {
    return FileType.byName[path];
  }

  @override
  int xAccess(String path, int flags) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.xAccess(path, flags);
    } else {
      final files = _requireFiles();
      return files.exists(type) ? 1 : 0;
    }
  }

  @override
  void xDelete(String path, int syncDir) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.xDelete(path, syncDir);
    } else {
      _requireFiles().markExists(type, false);
    }
  }

  @override
  String xFullPathName(String path) {
    return pathToAbsoluteAndNormalize(path);
  }

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final pathStr = path.path;
    if (pathStr == null) return _memory.xOpen(path, flags);

    final recognized = _recognizeType(pathStr);
    if (recognized == null) return _memory.xOpen(path, flags);

    final files = _requireFiles();
    final create = (flags & SqlFlag.SQLITE_OPEN_CREATE) != 0;
    final deleteOnClose = (flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE) != 0;
    final existsAlready = files.exists(recognized);

    if (!existsAlready) {
      if (create) {
        final syncHandle = files.handleFor(recognized);
        syncHandle.truncate(0);
        files.markExists(recognized, true);
      } else {
        throw const VfsException(SqlError.SQLITE_CANTOPEN);
      }
    }

    return (
      outFlags: 0,
      file: _SimpleOpfsFile(this, recognized, deleteOnClose),
    );
  }

  @override
  void xSleep(Duration duration) {}

  /// Closes the synchronous access handles kept open while this file system is
  /// active.
  ///
  /// This file system can be re-opened afterwards with [open].
  void close() {
    _files?.close();
    _files = null;
  }

  /// Re-opens a file system previously closed with [close].
  @experimental
  Future<void> open(
    FileSystemDirectoryHandle root, {
    bool readWriteUnsafe = false,
  }) async {
    assert(_files == null);

    Future<FileSystemSyncAccessHandle> open(String name) async {
      final handle = await root.openFile(name, create: true);

      final syncHandlePromise = readWriteUnsafe
          ? ProposedLockingSchemeApi(handle).createSyncAccessHandle(
              FileSystemCreateSyncAccessHandleOptions.unsafeReadWrite(),
            )
          : handle.createSyncAccessHandle();

      return await syncHandlePromise.toDart;
    }

    final meta = await open('meta');
    meta.truncate(2);

    final database = await open(FileType.database.name);
    final journal = await open(FileType.journal.name);
    _files = _OpfsFiles(meta, database, journal);
  }
}

class _SimpleOpfsFile extends BaseVfsFile {
  final SimpleOpfsFileSystem vfs;
  final FileType type;
  final bool deleteOnClose;

  var _lockMode = SqlFileLockingLevels.SQLITE_LOCK_NONE;

  FileSystemSyncAccessHandle get syncHandle =>
      vfs._requireFiles().handleFor(type);

  _SimpleOpfsFile(this.vfs, this.type, this.deleteOnClose);

  @override
  int readInto(Uint8List buffer, int offset) {
    return syncHandle.readDart(buffer, FileSystemReadWriteOptions(at: offset));
  }

  @override
  int xCheckReservedLock() {
    return _lockMode >= SqlFileLockingLevels.SQLITE_LOCK_RESERVED ? 1 : 0;
  }

  @override
  void xClose() {
    syncHandle.flush();

    if (deleteOnClose) {
      vfs._requireFiles().markExists(type, false);
    }
  }

  @override
  int xFileSize() {
    return syncHandle.getSize();
  }

  @override
  void xLock(int mode) {
    _lockMode = mode;
  }

  @override
  void xSync(int flags) {
    syncHandle.flush();
  }

  @override
  void xTruncate(int size) {
    syncHandle.truncate(size);
  }

  @override
  void xUnlock(int mode) {
    _lockMode = mode;
  }

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    final bytesWritten = syncHandle.writeDart(
      buffer,
      FileSystemReadWriteOptions(at: fileOffset),
    );

    if (bytesWritten < buffer.length) {
      throw const VfsException(SqlExtendedError.SQLITE_IOERR_WRITE);
    }
  }
}

final class _OpfsFiles {
  final Uint8List _existsList = Uint8List(FileType.values.length);

  final FileSystemSyncAccessHandle metaHandle;
  final FileSystemSyncAccessHandle database;
  final FileSystemSyncAccessHandle journal;

  _OpfsFiles(this.metaHandle, this.database, this.journal);

  bool exists(FileType type) {
    metaHandle.readDart(_existsList, FileSystemReadWriteOptions(at: 0));
    return _existsList[type.index] != 0;
  }

  void markExists(FileType type, bool exists) {
    _existsList[type.index] = exists ? 1 : 0;
    metaHandle.writeDart(_existsList, FileSystemReadWriteOptions(at: 0));
  }

  FileSystemSyncAccessHandle handleFor(FileType type) {
    return switch (type) {
      FileType.database => database,
      FileType.journal => journal,
    };
  }

  void close() {
    metaHandle.close();
    database.close();
    journal.close();
  }
}
