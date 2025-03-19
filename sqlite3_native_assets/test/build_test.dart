import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_native_assets/sqlite3_native_assets.dart';
import 'package:test/test.dart';

void main() {
  final sqlite3 = sqlite3Native;
  late Database database;

  setUp(() => database = sqlite3.openInMemory());
  tearDown(() => database.dispose());

  group('compiled sqlite3', () {
    test('enables fts5', () {
      database.execute('CREATE VIRTUAL TABLE foo USING fts5(a, b, c);');
    });

    test('enables rtree', () {
      database.execute('CREATE VIRTUAL TABLE foo USING rtree(a, b, c);');
    });

    test('enables math functions', () {
      final [row] = database.select('SELECT sin(pi());');
      expect(row.values, [closeTo(0, 0.00001)]);
    });

    test('disables double-quoted string literals by default', () {
      expect(
        () => database.execute('SELECT "not a string";'),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
