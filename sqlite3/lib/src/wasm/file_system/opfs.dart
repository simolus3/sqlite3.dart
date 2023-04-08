import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../constants.dart';
import '../file_system.dart';
import '../js_interop.dart';

@internal
enum FileType {
  database('/database'),
  journal('/database-journal');

  final String filePath;

  const FileType(this.filePath);

  static final byName = {
    for (final entry in values) entry.filePath: entry,
  };

  static final _validNames = values.map((e) => e.filePath).join(', ');
}

/// A [FileSystem] for the `sqlite3` wasm library based on the [file system access API].
///
/// By design, this file system can only store two files: `/database` and
/// `/database-journal`. Thus, when this file system is used, the only sqlite3
/// database that will be persisted properly is the one at `/database`.
///
/// The limitation of only being able to store two files comes from the fact
/// that we can't synchronously _open_ files in with the file system access API,
/// only reads and writes are synchronous.
/// By having a known amount of files to store, we can simply open both files
/// in [OpfsFileSystem.inDirectory] or [OpfsFileSystem.loadFromStorage], which
/// is asynchronous too. The actual file system work, which needs to be
/// synchronous for sqlite3 to function, does not need any further wrapper.
///
/// Please note that [OpfsFileSystem]s are only available in dedicated web workers,
/// not in the JavaScript context for a tab or a shared web worker.
///
/// [file system access API]: https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API
class OpfsFileSystem implements FileSystem {
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

  final FileSystemSyncAccessHandle _metaHandle;
  final Map<FileType, FileSystemSyncAccessHandle> _files;

  final FileSystem _memory = FileSystem.inMemory();
  final Uint8List _existsList = Uint8List(FileType.values.length);

  OpfsFileSystem._(this._metaHandle, this._files);

  /// Loads an [OpfsFileSystem] in the desired [path] under the root directory
  /// for OPFS as given by `navigator.storage.getDirectory()` in JavaScript.
  ///
  /// Throws a [FileSystemException] if OPFS is not available - please note that
  /// this file system implementation requires a recent browser and only works
  /// in dedicated web workers.
  static Future<OpfsFileSystem> loadFromStorage(String path) async {
    final storage = storageManager;
    if (storage == null) {
      throw FileSystemException(
          SqlError.SQLITE_ERROR, 'storageManager not supported by browser');
    }

    var opfsDirectory = await storage.directory;

    for (final segment in p.split(path)) {
      opfsDirectory = await opfsDirectory.getDirectory(segment, create: true);
    }

    return inDirectory(opfsDirectory);
  }

  /// Loads an [OpfsFileSystem] in the desired [root] directory, which must be
  /// a Dart wrapper around a [FileSystemDirectoryHandle].
  ///
  /// [FileSystemDirectoryHandle]: https://developer.mozilla.org/en-US/docs/Web/API/FileSystemDirectoryHandle
  static Future<OpfsFileSystem> inDirectory(Object root) async {
    Future<FileSystemSyncAccessHandle> open(String name) async {
      final handle = await (root as FileSystemDirectoryHandle)
          .openFile(name, create: true);
      return await handle.createSyncAccessHandle();
    }

    final meta = await open('meta');
    meta.truncate(2);
    final files = {
      for (final type in FileType.values) type: await open(type.name)
    };

    return OpfsFileSystem._(meta, files);
  }

  void _markExists(FileType type, bool exists) {
    _existsList[type.index] = exists ? 1 : 0;
    _metaHandle.write(_existsList, FileSystemReadWriteOptions(at: 0));
  }

  FileType? _recognizeType(String path) {
    return FileType.byName[path];
  }

  @override
  void clear() {
    _memory.clear();

    for (final entry in _files.keys) {
      _existsList[entry.index] = 0;
    }
    _metaHandle.write(_existsList, FileSystemReadWriteOptions(at: 0));
  }

  @override
  void createFile(String path,
      {bool errorIfNotExists = false, bool errorIfAlreadyExists = false}) {
    final type = _recognizeType(path);
    if (type == null) {
      throw ArgumentError.value(
        path,
        'path',
        'Invalid path for OPFS file system, only ${FileType._validNames} are '
            'supported!',
      );
    } else {
      _metaHandle.read(_existsList, FileSystemReadWriteOptions(at: 0));
      final exists = _existsList[type.index] != 0;

      if ((exists && errorIfAlreadyExists) || (!exists && errorIfNotExists)) {
        throw FileSystemException();
      }

      if (!exists) {
        _markExists(type, true);
        _files[type]!.truncate(0);
      }
    }
  }

  @override
  String createTemporaryFile() {
    return _memory.createTemporaryFile();
  }

  @override
  void deleteFile(String path) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.deleteFile(path);
    } else {
      _markExists(type, false);
    }
  }

  @override
  bool exists(String path) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.exists(path);
    } else {
      _metaHandle.read(_existsList, FileSystemReadWriteOptions(at: 0));
      return _existsList[type.index] != 0;
    }
  }

  @override
  List<String> get files {
    final existsStats = Uint8List(FileType.values.length);
    _metaHandle.read(existsStats, FileSystemReadWriteOptions(at: 0));

    return [
      for (final type in FileType.values)
        if (existsStats[type.index] != 0) type.filePath,
      ..._memory.files,
    ];
  }

  @override
  int read(String path, Uint8List target, int offset) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.read(path, target, offset);
    } else {
      return _files[type]!.read(target, FileSystemReadWriteOptions(at: offset));
    }
  }

  @override
  int sizeOfFile(String path) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.sizeOfFile(path);
    } else {
      return _files[type]!.getSize();
    }
  }

  @override
  void truncateFile(String path, int length) {
    final type = _recognizeType(path);
    if (type == null) {
      _memory.truncateFile(path, length);
    } else {
      _files[type]!.truncate(length);
    }
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    final type = _recognizeType(path);
    if (type == null) {
      _memory.write(path, bytes, offset);
    } else {
      _files[type]!.write(bytes, FileSystemReadWriteOptions(at: offset));
    }
  }

  void close() {
    _metaHandle.close();
    for (final entry in _files.values) {
      entry.close();
    }
  }
}
