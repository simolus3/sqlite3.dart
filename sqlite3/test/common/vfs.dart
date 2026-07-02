import 'dart:async';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:test/test.dart';

import 'utils.dart';

void testVfs(FutureOr<CommonSqlite3> Function() loadSqlite) {
  late CommonSqlite3 sqlite3;

  setUpAll(() async => sqlite3 = await loadSqlite());

  test('smoke check', () {
    final vfs = InMemoryFileSystem(name: 'dart');
    sqlite3.registerVirtualFileSystem(vfs);
    addTearDown(() => sqlite3.unregisterVirtualFileSystem(vfs));

    expect(vfs.xAccess('/database', 0), isZero);
    var database = sqlite3.open('/database', vfs: 'dart');
    database.execute('CREATE TABLE foo (bar TEXT);');
    database.execute('INSERT INTO foo (bar) VALUES (?)', ['first row']);
    expect(vfs.xAccess('/database', 0), isPositive);

    database.close();
    database = sqlite3.open('/database', vfs: 'dart');
    expect(database.select('SELECT * FROM foo'), hasLength(1));
    database.close();
  });

  test("can't use vfs after unregistering it", () {
    final vfs = InMemoryFileSystem(name: 'dart');
    sqlite3.registerVirtualFileSystem(vfs);

    sqlite3.open('/database', vfs: 'dart').close();
    sqlite3.unregisterVirtualFileSystem(vfs);

    expect(() => sqlite3.open('/database', vfs: 'dart'), throwsSqlError(1, 1));
  });

  test('reports current time', () {
    final memory = InMemoryFileSystem();
    final vfs = TestVfs('dart')
      ..xOpenDelegate = memory.xOpen
      ..xCurrentTimeDelegate = () => DateTime.utc(2024, 11, 19);
    sqlite3.registerVirtualFileSystem(vfs);
    addTearDown(() => sqlite3.unregisterVirtualFileSystem(vfs));

    final database = sqlite3.openInMemory(vfs: 'dart');
    addTearDown(database.close);

    expect(database.select('SELECT CURRENT_TIMESTAMP AS r'), [
      {'r': '2024-11-19 00:00:00'},
    ]);
  });

  test('can use temporary files', () {
    final memory = InMemoryFileSystem(name: 'dart-tmp');
    sqlite3.registerVirtualFileSystem(memory);
    addTearDown(() => sqlite3.unregisterVirtualFileSystem(memory));

    final db = sqlite3.open('/db', vfs: 'dart-tmp');
    addTearDown(db.close);

    db.execute('CREATE TEMP TABLE foo (bar TEXT);');
    final insert = db.prepare('INSERT INTO foo (bar) VALUES (?);');
    final data = 'new row' * 100;
    for (var i = 0; i < 10000; i++) {
      insert.execute([data]);
    }
    insert.close();
  });

  test(
    'can use atomic writes',
    () {
      final vfs = _AtomicWritesVfs(name: 'dart-atomic');
      sqlite3.registerVirtualFileSystem(vfs);
      addTearDown(() => sqlite3.unregisterVirtualFileSystem(vfs));

      final db = sqlite3.open('/db', vfs: vfs.name);
      addTearDown(db.close);

      db.execute('CREATE TABLE foo (bar TEXT)');
      // The first transaction creating a database file will always use a journal.
      expect(vfs.fileControlEvents, isEmpty);

      db.execute('INSERT INTO foo DEFAULT VALUES');
      expect(vfs.fileControlEvents, [
        SqliteFileControl.beginAtomicWrite,
        SqliteFileControl.commitAtomicWrite,
      ]);
    },
    // This test requires SQLITE_ENABLE_BATCH_ATOMIC_WRITE.
    tags: 'require_built',
  );
}

final class TestVfs extends VirtualFileSystem {
  TestVfs(super.name);

  int Function(String, int) xAccessDelegate = (_, _) => 0;
  DateTime Function() xCurrentTimeDelegate = DateTime.now;
  void Function(String, int)? xDeleteDelegate;
  String Function(String) xFullPathNameDelegate = (_) =>
      throw UnimplementedError();
  XOpenResult Function(Sqlite3Filename path, int flags) xOpenDelegate =
      (path, flags) => throw UnimplementedError();
  void Function(Uint8List)? xRandomnessDelegate;
  void Function(Duration)? xSleepDelegate;

  @override
  int xAccess(String path, int flags) {
    return xAccessDelegate(path, flags);
  }

  @override
  DateTime xCurrentTime() {
    return xCurrentTimeDelegate();
  }

  @override
  void xDelete(String path, int syncDir) {
    return xDeleteDelegate?.call(path, syncDir);
  }

  @override
  String xFullPathName(String path) {
    return xFullPathNameDelegate(path);
  }

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    return xOpenDelegate(path, flags);
  }

  @override
  void xRandomness(Uint8List target) {
    return xRandomnessDelegate?.call(target);
  }

  @override
  void xSleep(Duration duration) {
    xSleepDelegate?.call(duration);
  }
}

final class _AtomicWritesVfs extends BaseVirtualFileSystem {
  final InMemoryFileSystem memory = InMemoryFileSystem();
  final List<SqliteFileControl> fileControlEvents = [];

  _AtomicWritesVfs({required super.name});

  @override
  int xAccess(String path, int flags) => memory.xAccess(path, flags);

  @override
  void xDelete(String path, int syncDir) => memory.xDelete(path, syncDir);

  @override
  String xFullPathName(String path) => memory.xFullPathName(path);

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final result = memory.xOpen(path, flags);
    return (
      outFlags: result.outFlags,
      file: _AtomicWriteFile(result.file, this),
    );
  }

  @override
  void xSleep(Duration duration) {}
}

final class _AtomicWriteFile implements VirtualFileSystemFile {
  final VirtualFileSystemFile _memoryFile;
  final _AtomicWritesVfs _vfs;

  Map<int, Uint8List>? batchedWrite;

  _AtomicWriteFile(this._memoryFile, this._vfs);

  @override
  int get xDeviceCharacteristics {
    return SqlDeviceCharacteristics.SQLITE_IOCAP_BATCH_ATOMIC;
  }

  @override
  void xRead(Uint8List target, int fileOffset) {
    return _memoryFile.xRead(target, fileOffset);
  }

  @override
  int xCheckReservedLock() => _memoryFile.xCheckReservedLock();

  @override
  void xClose() => _memoryFile.xClose();

  @override
  int xFileSize() => _memoryFile.xFileSize();

  @override
  void xLock(int mode) => _memoryFile.xLock(mode);

  @override
  void xSync(int flags) => _memoryFile.xSync(flags);

  @override
  void xTruncate(int size) => _memoryFile.xTruncate(size);

  @override
  void xUnlock(int mode) => _memoryFile.xUnlock(mode);

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    if (batchedWrite case final batch?) {
      batch[fileOffset] = buffer;
    } else {
      _memoryFile.xWrite(buffer, fileOffset);
    }
  }

  @override
  int xFileControl(SqliteFileControl op, int ptr) {
    switch (op) {
      case SqliteFileControl.beginAtomicWrite:
        _vfs.fileControlEvents.add(op);
        assert(batchedWrite == null);
        batchedWrite = {};
        return SqlError.SQLITE_OK;
      case SqliteFileControl.commitAtomicWrite:
        _vfs.fileControlEvents.add(op);
        assert(batchedWrite != null);
        batchedWrite!.forEach(
          (offset, bytes) => _memoryFile.xWrite(bytes, offset),
        );

        batchedWrite = null;
        return SqlError.SQLITE_OK;
      case SqliteFileControl.rollbackAtomicWrite:
        _vfs.fileControlEvents.add(op);
        assert(batchedWrite != null);
        batchedWrite = null;
        return SqlError.SQLITE_OK;
    }

    return SqlError.SQLITE_NOTFOUND;
  }
}
