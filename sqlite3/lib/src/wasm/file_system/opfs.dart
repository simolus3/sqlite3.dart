import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../constants.dart';
import '../file_system.dart';
import '../js_interop.dart';

enum FileType {
  database('/database'),
  journal('/database-journal');

  final String filePath;

  const FileType(this.filePath);

  static final byName = {
    for (final entry in values) entry.filePath: entry,
  };
}

class OpfsFileSystem implements FileSystem {
  final FileSystemSyncAccessHandle _metaHandle;
  final Map<FileType, FileSystemSyncAccessHandle> _files;

  final FileSystem _memory = FileSystem.inMemory();

  final Uint8List _oneByteList = Uint8List(1);

  OpfsFileSystem._(this._metaHandle, this._files);

  static Future<OpfsFileSystem> loadFromStorage(String root) async {
    final storage = storageManager;
    if (storage == null) {
      throw FileSystemException(
          SqlError.SQLITE_ERROR, 'storageManager not supported by browser');
    }

    var opfsDirectory = await storage.directory;

    for (final segment in p.split(root)) {
      opfsDirectory = await opfsDirectory.getDirectory(segment, create: true);
    }

    return inDirectory(opfsDirectory);
  }

  static Future<OpfsFileSystem> inDirectory(
      FileSystemDirectoryHandle root) async {
    Future<FileSystemSyncAccessHandle> open(String name) async {
      final handle = await root.openFile(name, create: true);
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
    _oneByteList[0] = exists ? 1 : 0;
    _metaHandle.write(_oneByteList, FileSystemReadWriteOptions(at: type.index));
  }

  FileType? _recognizeType(String path) {
    return FileType.byName[path];
  }

  @override
  void clear() {
    _memory.clear();

    for (final entry in _files.keys) {
      _markExists(entry, false);
    }
  }

  @override
  void createFile(String path,
      {bool errorIfNotExists = false, bool errorIfAlreadyExists = false}) {
    final type = _recognizeType(path);
    if (type == null) {
      return _memory.createFile(
        path,
        errorIfAlreadyExists: errorIfAlreadyExists,
        errorIfNotExists: errorIfNotExists,
      );
    } else {
      _metaHandle.read(
          _oneByteList, FileSystemReadWriteOptions(at: type.index));
      final exists = _oneByteList[0] != 0;

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
      _metaHandle.read(
          _oneByteList, FileSystemReadWriteOptions(at: type.index));
      return _oneByteList[0] != 0;
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
