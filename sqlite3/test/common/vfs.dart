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

    database.dispose();
    database = sqlite3.open('/database', vfs: 'dart');
    expect(database.select('SELECT * FROM foo'), hasLength(1));
    database.dispose();
  });

  test("can't use vfs after unregistering it", () {
    final vfs = InMemoryFileSystem(name: 'dart');
    sqlite3.registerVirtualFileSystem(vfs);

    sqlite3.open('/database', vfs: 'dart').dispose();
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
    addTearDown(database.dispose);

    expect(database.select('SELECT CURRENT_TIMESTAMP AS r'), [
      {'r': '2024-11-19 00:00:00'}
    ]);
  });
}

final class TestVfs extends VirtualFileSystem {
  TestVfs(super.name);

  int Function(String, int) xAccessDelegate = (_, __) => 0;
  DateTime Function() xCurrentTimeDelegate = DateTime.now;
  void Function(String, int)? xDeleteDelegate;
  String Function(String) xFullPathNameDelegate =
      (_) => throw UnimplementedError();
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
