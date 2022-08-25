@Tags(['wasm'])
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  late WasmSqlite3 sqlite3;

  setUpAll(() async => sqlite3 = await loadSqlite3());

  test('get version', () {
    final version = sqlite3.version;
    expect(
      version,
      isA<Version>()
          .having((e) => e.libVersion, 'libVersion', startsWith('3.39')),
    );
  });

  test('can use current date', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    final results = db.select("SELECT strftime('%s', CURRENT_TIMESTAMP) AS r");
    final row = results.single['r'] as String;

    expect(int.parse(row),
        closeTo(DateTime.now().millisecondsSinceEpoch ~/ 1000, 5));
  });
}
