/// Provides a virtual filesystem implementation for SQLite based on the `file`
/// and `clock` packages.
///
/// This makes it easier to use SQLite in tests, as SQL constructs like
/// `CURRENT_TIMESTAMP` will reflect the fake time of `package:clock`, allowing
/// SQL logic relying on time to be tested reliably. Additionally, using
/// `dart:clock` allows testing the IO behavior of SQLite databases if
/// necessary.
library;

import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:file/file.dart';
import 'package:sqlite3/common.dart';

final class TestSqliteFileSystem extends BaseVirtualFileSystem {
  static int _counter = 0;

  final FileSystem _fs;
  Directory? _createdTmp;
  int _tmpFileCounter = 0;

  TestSqliteFileSystem({required FileSystem fs, String? name})
      : _fs = fs,
        super(name: name ?? 'dart-test-vfs-${_counter++}');

  Directory get _tempDirectory {
    return _createdTmp ??=
        _fs.systemTempDirectory.createTempSync('dart-sqlite3-test');
  }

  @override
  int xAccess(String path, int flags) {
    switch (flags) {
      case 0:
        // Exists
        return _fs.typeSync(path) == FileSystemEntityType.file ? 1 : 0;
      default:
        // Check readable and writable
        try {
          final file = _fs.file(path);
          file.openSync(mode: FileMode.write).closeSync();
          return 1;
        } on IOException {
          return 0;
        }
    }
  }

  @override
  DateTime xCurrentTime() {
    return clock.now();
  }

  @override
  void xDelete(String path, int syncDir) {
    _fs.file(path).deleteSync();
  }

  @override
  String xFullPathName(String path) {
    return _fs.path.absolute(path);
  }

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final fsPath = path.path ??
        _tempDirectory.childFile((_tmpFileCounter++).toString()).absolute.path;
    final type = _fs.typeSync(fsPath);

    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw VfsException(ErrorCodes.EINVAL);
    }

    if (flags & SqlFlag.SQLITE_OPEN_EXCLUSIVE != 0 &&
        type != FileSystemEntityType.notFound) {
      throw VfsException(ErrorCodes.EEXIST);
    }
    if (flags & SqlFlag.SQLITE_OPEN_CREATE != 0 &&
        type == FileSystemEntityType.notFound) {
      _fs.file(fsPath).createSync();
    }

    final deleteOnClose = flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE != 0;
    final readonly = flags & SqlFlag.SQLITE_OPEN_READONLY != 0;
    final vsFile = _fs.file(fsPath);
    final file =
        vsFile.openSync(mode: readonly ? FileMode.read : FileMode.write);

    return (
      file: _TestFile(vsFile, file, deleteOnClose),
      outFlags: readonly ? SqlFlag.SQLITE_OPEN_READONLY : 0,
    );
  }

  @override
  void xSleep(Duration duration) {}
}

final class _TestFile implements VirtualFileSystemFile {
  final File _path;
  final RandomAccessFile _file;
  final bool _deleteOnClose;
  int _lockLevel = SqlFileLockingLevels.SQLITE_LOCK_NONE;

  _TestFile(this._path, this._file, this._deleteOnClose);

  @override
  void xClose() {
    _file.closeSync();
    if (_deleteOnClose) {
      _path.deleteSync();
    }
  }

  @override
  int get xDeviceCharacteristics => 0;

  @override
  int xFileSize() => _file.lengthSync();

  @override
  void xRead(Uint8List target, int fileOffset) {
    _file.setPositionSync(fileOffset);
    final bytesRead = _file.readIntoSync(target);
    if (bytesRead < target.length) {
      target.fillRange(bytesRead, target.length, 0);
      throw VfsException(SqlExtendedError.SQLITE_IOERR_SHORT_READ);
    }
  }

  @override
  void xSync(int flags) {
    _file.flushSync();
  }

  @override
  void xTruncate(int size) {
    _file.truncateSync(size);
  }

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    _file
      ..setPositionSync(fileOffset)
      ..writeFromSync(buffer);
  }

  @override
  int xCheckReservedLock() {
    // RandomAccessFile doesn't appear to expose information on whether another
    // process is holding locks.
    return _lockLevel > SqlFileLockingLevels.SQLITE_LOCK_NONE ? 1 : 0;
  }

  @override
  void xLock(int mode) {
    if (_lockLevel >= mode) {
      return;
    }

    if (_lockLevel != SqlFileLockingLevels.SQLITE_LOCK_NONE) {
      // We want to upgrade our lock, which we do by releasing it and then
      // re-obtaining it.
      _file.unlockSync();
      _lockLevel = SqlFileLockingLevels.SQLITE_LOCK_NONE;
    }

    final exclusive = mode > SqlFileLockingLevels.SQLITE_LOCK_SHARED;
    _file.lockSync(
        exclusive ? FileLock.blockingExclusive : FileLock.blockingShared);
    _lockLevel = mode;
  }

  @override
  void xUnlock(int mode) {
    if (_lockLevel < mode) {
      return;
    }

    _file.unlockSync();
    if (mode != SqlFileLockingLevels.SQLITE_LOCK_NONE) {
      return xLock(mode);
    }
  }
}
