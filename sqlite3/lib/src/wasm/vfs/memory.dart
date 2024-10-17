import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'dynamic_buffer.dart';

import '../../constants.dart';
import '../../vfs.dart';
import 'utils.dart';

final class InMemoryFileSystem extends BaseVirtualFileSystem {
  final Map<String, DynamicBuffer?> fileData = {};

  InMemoryFileSystem({super.name = 'dart-memory', super.random});

  @override
  int xAccess(String path, int flags) {
    return fileData.containsKey(path) ? 1 : 0;
  }

  @override
  void xDelete(String path, int syncDir) {
    fileData.remove(path);
  }

  @override
  String xFullPathName(String path) {
    return p.url.normalize('/$path');
  }

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final pathStr = path.path ?? random.randomFileName(prefix: '/');
    if (!fileData.containsKey(pathStr)) {
      final create = flags & SqlFlag.SQLITE_OPEN_CREATE;

      if (create != 0) {
        fileData[pathStr] = DynamicBuffer();
      } else {
        throw VfsException(SqlError.SQLITE_CANTOPEN);
      }
    }

    return (
      outFlags: 0,
      file: _InMemoryFile(
        this,
        pathStr,
        flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE != 0,
      ),
    );
  }

  @override
  void xSleep(Duration duration) {}
}

class _InMemoryFile extends BaseVfsFile {
  final InMemoryFileSystem vfs;
  final String path;
  final bool deleteOnClose;

  var _lockMode = SqlFileLockingLevels.SQLITE_LOCK_NONE;

  _InMemoryFile(this.vfs, this.path, this.deleteOnClose);

  @override
  int readInto(Uint8List buffer, int offset) {
    final file = vfs.fileData[path];
    if (file == null || file.length <= offset) return 0;

    final available = min(buffer.length, file.length - offset);
    buffer.setRange(0, available, file.toUint8List(), offset);
    return available;
  }

  @override
  int xCheckReservedLock() {
    return _lockMode >= SqlFileLockingLevels.SQLITE_LOCK_RESERVED ? 1 : 0;
  }

  @override
  void xClose() {
    if (deleteOnClose) {
      vfs.xDelete(path, 0);
    }
  }

  @override
  int xFileSize() {
    return vfs.fileData[path]!.length;
  }

  @override
  void xLock(int mode) {
    _lockMode = mode;
  }

  @override
  void xSync(int flags) {}

  @override
  void xTruncate(int size) {
    final file = vfs.fileData[path];

    if (file == null) {
      vfs.fileData[path] = DynamicBuffer();
      vfs.fileData[path]!.truncate(size);
    } else {
      file.truncate(size);
    }
  }

  @override
  void xUnlock(int mode) {
    _lockMode = mode;
  }

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    var file = vfs.fileData[path];

    if (file == null) {
      file = DynamicBuffer();
      vfs.fileData[path] = file;
    }
    file.write(buffer, fileOffset);
  }
}
