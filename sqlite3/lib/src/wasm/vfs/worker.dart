import 'dart:html';

import 'package:js/js.dart';
import 'package:path/path.dart' as p show url;

import '../../constants.dart';
import '../../vfs.dart';
import '../js_interop.dart';
import 'sync_channel.dart';

const _workerDebugLog =
    bool.fromEnvironment('sqlite3.wasm.worker.debug', defaultValue: false);

void _log(String message) {
  print(message);
}

@JS()
@anonymous
class WorkerOptions {
  external int get clientVersion;
  external String get root;
  external SharedArrayBuffer get synchronizationBuffer;
  external SharedArrayBuffer get communicationBuffer;

  external factory WorkerOptions._({
    required int clientVersion,
    required String root,
    required SharedArrayBuffer synchronizationBuffer,
    required SharedArrayBuffer communicationBuffer,
  });

  factory WorkerOptions({
    int clientVersion = protocolVersion,
    String root = 'pkg_sqlite3_db/',
    required SharedArrayBuffer synchronizationBuffer,
    required SharedArrayBuffer communicationBuffer,
  }) {
    return WorkerOptions._(
      clientVersion: clientVersion,
      root: root,
      synchronizationBuffer: synchronizationBuffer,
      communicationBuffer: communicationBuffer,
    );
  }
}

class VfsWorker {
  final RequestResponseSynchronizer synchronizer;
  final MessageSerializer messages;

  final FileSystemDirectoryHandle root;

  var _fdCounter = 0;
  final Map<int, _OpenedFileHandle> _openFiles = {};
  final Set<_OpenedFileHandle> _implicitlyHeldLocks = {};

  var _shutdownRequested = false;

  VfsWorker._(WorkerOptions options, this.root)
      : synchronizer =
            RequestResponseSynchronizer(options.synchronizationBuffer),
        messages = MessageSerializer(options.communicationBuffer);

  static Future<VfsWorker> create(WorkerOptions options) async {
    var root = await storageManager!.directory;
    final split = p.url.split(options.root);

    for (final directory in split) {
      root = await root.getDirectory(directory, create: true);
    }

    return VfsWorker._(options, root);
  }

  Future<(FileSystemDirectoryHandle, String, String)> _resolvePath(
      String absolutePath,
      {bool createDirectories = false}) async {
    final fullPath = p.url.relative(absolutePath, from: '/');
    final [...dir, file] = p.url.split(fullPath);

    var dirHandle = root;
    for (final entry in dir) {
      dirHandle =
          await dirHandle.getDirectory(entry, create: createDirectories);
    }

    return (dirHandle, fullPath, file);
  }

  Future<Flags> _xAccess(NameAndInt32Flags flags) async {
    var rc = 0;

    try {
      final (dir, _, fileName) = await _resolvePath(flags.name);

      // If we can open the file, it exists. For OPFS, that means that it's both
      // readable and writable.
      await dir.openFile(fileName);
    } catch (e) {
      rc = SqlError.SQLITE_IOERR;
    }

    return Flags(rc, 0, 0);
  }

  Future<Flags> _xOpen(NameAndInt32Flags req) async {
    final flags = req.flag0;
    final create = (flags & SqlFlag.SQLITE_OPEN_CREATE) != 0;

    FileSystemDirectoryHandle directory;
    String fullPath, fileName;

    try {
      (directory, fullPath, fileName) =
          await _resolvePath(req.name, createDirectories: create);
    } catch (e) {
      // Error traversing the path
      throw VfsException(SqlError.SQLITE_NOTFOUND);
    }

    final fileHandle = await directory.openFile(fileName, create: create);
    final readonly = !create && (flags & SqlFlag.SQLITE_OPEN_READONLY) != 0;
    final opened = _OpenedFileHandle(
      fd: _fdCounter++,
      directory: directory,
      fullPath: fullPath,
      filename: fileName,
      file: fileHandle,
      deleteOnClose: (flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE) != 0,
      readonly: readonly,
    );
    _openFiles[opened.fd] = opened;

    var outFlags = 0;
    if (readonly) {
      outFlags |= SqlFlag.SQLITE_OPEN_READONLY;
    }

    // flag0 are the outFlags passed to sqlite, flag1 is the descriptor
    return Flags(outFlags, opened.fd, 0);
  }

  Future<void> _xClose(Flags req) async {
    final file = _openFiles.remove(req.flag0);
    _implicitlyHeldLocks.remove(file);

    if (file == null) {
      throw const VfsException(SqlError.SQLITE_NOTFOUND);
    }

    _closeSyncHandle(file);
    if (file.deleteOnClose) {
      await file.directory.removeEntry(file.filename);
    }
  }

  Future<Flags> _xFileSize(Flags req) async {
    final file = _openFiles[req.flag0]!;
    try {
      final syncHandle = await _openForSynchronousAccess(file);
      final size = syncHandle.getSize();

      return Flags(size, 0, 0);
    } finally {
      _releaseImplicitLock(file);
    }
  }

  Future<EmptyMessage> _xTruncate(Flags req) async {
    final file = _openFiles[req.flag0]!;
    try {
      final syncHandle = await _openForSynchronousAccess(file);
      syncHandle.truncate(req.flag1);
    } finally {
      _releaseImplicitLock(file);
    }

    return const EmptyMessage();
  }

  Future<void> start() async {
    while (!_shutdownRequested) {
      final waitResult = synchronizer.waitForRequest();
      if (waitResult == Atomics.timedOut) {
        // No requests for some time, transition to idle
        _releaseImplicitLocks();
        continue;
      }

      final opcode = WorkerOperation.values[synchronizer.takeOpcode()];
      Object? request;
      int rc;

      try {
        Message response;
        request = opcode.readRequest(messages);

        switch (opcode) {
          case WorkerOperation.xAccess:
            response = await _xAccess(request as NameAndInt32Flags);
            break;
          case WorkerOperation.xOpen:
            response = await _xOpen(request as NameAndInt32Flags);
            break;
          case WorkerOperation.xClose:
            await _xClose(request as Flags);
            response = EmptyMessage();
            break;
          case WorkerOperation.xFileSize:
            response = await _xFileSize(request as Flags);
            break;
          case WorkerOperation.xTruncate:
            response = await _xTruncate(request as Flags);
            break;
        }

        messages.write(response);
        rc = 0;
      } on VfsException catch (e) {
        _log('Caught $e while handling $opcode($request)');
        rc = e.returnCode;
      } catch (e) {
        _log('Caught $e while handling $opcode($request)');
        rc = 1;
      }

      synchronizer.respond(rc);
    }
  }

  void _releaseImplicitLocks() {
    _implicitlyHeldLocks.forEach(_releaseImplicitLock);
  }

  void _releaseImplicitLock(_OpenedFileHandle handle) {
    if (_implicitlyHeldLocks.remove(handle)) {
      _closeSyncHandleNoThrow(handle);
    }
  }

  Future<FileSystemSyncAccessHandle> _openForSynchronousAccess(
      _OpenedFileHandle file) async {
    final existing = file.syncHandle;
    if (existing != null) {
      return existing;
    }

    var attempt = 1;
    const maxAttempts = 6;

    while (true) {
      try {
        final handle =
            file.syncHandle = await file.file.createSyncAccessHandle();

        // We've locked the file simply because we've created an (exclusive)
        // synchronous access handle. If there was no explicit lock on this
        // file (through xLock), let's remember that we've locked the file. For
        // most operations (e.g. subsequent reads and writes), we keep a lock
        // across requests.
        if (!file.explicitlyLocked) {
          _implicitlyHeldLocks.add(file);
          _log('Acquired implicit lock for ${file.fullPath}');
        }
        return handle;
      } catch (e) {
        if (attempt == maxAttempts) {
          throw const VfsException(SqlError.SQLITE_IOERR);
        }

        _log('Could not obtain sync handle (attempt $attempt / $maxAttempts)');
        attempt++;
      }
    }
  }

  void _closeSyncHandleNoThrow(_OpenedFileHandle handle) {
    try {
      _closeSyncHandle(handle);
    } catch (e) {
      _log('Ignoring error during close');
    }
  }

  void _closeSyncHandle(_OpenedFileHandle handle) {
    final syncHandle = handle.syncHandle;
    if (syncHandle != null) {
      _log('Closing sync handle for ${handle.fullPath}');
      handle.syncHandle = null;
      _implicitlyHeldLocks.remove(syncHandle);
      syncHandle.close();
    }
  }
}

class _OpenedFileHandle {
  final int fd;
  final bool readonly;
  final bool deleteOnClose;

  final String fullPath;
  final FileSystemDirectoryHandle directory;
  final String filename;
  final FileSystemFileHandle file;

  bool explicitlyLocked = false;
  FileSystemSyncAccessHandle? syncHandle;

  _OpenedFileHandle({
    required this.fd,
    required this.readonly,
    required this.deleteOnClose,
    required this.fullPath,
    required this.directory,
    required this.filename,
    required this.file,
  });
}
