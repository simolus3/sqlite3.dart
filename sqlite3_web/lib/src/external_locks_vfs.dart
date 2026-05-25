import 'dart:async';

import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

/// A [SimpleOpfsFileSystem] managed with external navigator locks.
///
/// Normally, only a single file handle can be opened for OPFS files, and the
/// process of opening these files is asynchronous. To allow multiple tabs to
/// access the same database, it is wrapped in external locks:
///
///  1. On browsers that support it, we use the `readwrite-unsafe` open mode to
///     pre-open the VFS. We still have to use navigator locks to avoid races.
///  2. On other browsers, we open the VFS when a tab wants to use the database
///     and close it afterwards. This is less efficient, but still works.
///
/// The web worker is responsible for calling [markHasExclusiveAccess] before
/// using the database in any way. In this package, databases are only accesssed
/// asynchronously, so we can check these external locks first.
///
/// This is a generalization of [WasmVfs] that doesn't require COOP + COEP
/// headers and has similar performance characteristics. On browsers with
/// `readwrite-unsafe` support, it's substantially faster.
final class ExternalLocksState {
  final SimpleOpfsFileSystem fs;

  /// The directory in which the database file and journal are stored.
  final web.FileSystemDirectoryHandle _directory;

  final bool readWriteUnsafe;
  bool _hasExclusiveAccess = false;

  ExternalLocksState._(this.fs, this._directory, this.readWriteUnsafe);

  static Future<ExternalLocksState> open({
    required String path,
    required String vfsName,
    required bool readWriteUnsafe,
  }) async {
    final directory = await SimpleOpfsFileSystem.resolveDirectory(path);
    final vfs = SimpleOpfsFileSystem(vfsName: vfsName);
    if (readWriteUnsafe) {
      // We can open this already
      // ignore: experimental_member_use
      await vfs.open(directory, readWriteUnsafe: true);
    }

    return ExternalLocksState._(vfs, directory, readWriteUnsafe);
  }

  Future<void> markHasExclusiveAccess() async {
    assert(!_hasExclusiveAccess);
    if (!readWriteUnsafe) {
      // ignore: experimental_member_use
      await fs.open(_directory);
    }

    _hasExclusiveAccess = true;
  }

  Future<void> releaseExclusiveAccess() async {
    assert(_hasExclusiveAccess);
    if (!readWriteUnsafe) {
      fs.close();
    }
    _hasExclusiveAccess = false;
  }
}
