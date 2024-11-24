import 'package:fake_async/fake_async.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_test/sqlite3_test.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';

void main() {
  late TestSqliteFileSystem vfs;

  setUpAll(() {
    vfs = TestSqliteFileSystem(fs: const LocalFileSystem());
    sqlite3.registerVirtualFileSystem(vfs);
  });
  tearDownAll(() => sqlite3.unregisterVirtualFileSystem(vfs));

  test('my test depending on database time', () {
    final database = sqlite3.openInMemory(vfs: vfs.name);
    addTearDown(database.dispose);

    // The VFS uses package:clock to get the current time, which can be
    // overridden for tests:
    final moonLanding = DateTime.utc(1969, 7, 20, 20, 18, 04);
    FakeAsync(initialTime: moonLanding).run((_) {
      final row = database.select('SELECT unixepoch(current_timestamp)').first;

      expect(row.columnAt(0), -14182916);
    });
  });
}
