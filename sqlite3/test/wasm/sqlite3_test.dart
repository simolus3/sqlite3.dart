@Tags(['wasm'])
import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  for (final throughFetch in [false, true]) {
    group(throughFetch ? 'with fetch' : 'manually', () {
      late WasmSqlite3 sqlite3;

      setUpAll(() async {
        if (throughFetch) {
          sqlite3 = await loadSqlite3();
        } else {
          final channel = spawnHybridUri('/test/wasm/asset_server.dart');
          final port = await channel.stream.first as int;

          final sqliteWasm =
              Uri.parse('http://localhost:$port/example/web/sqlite3.wasm');

          final response = await http.get(sqliteWasm);
          if (response.statusCode != 200) {
            throw StateError(
                'Could not load module (${response.statusCode} ${response.body})');
          }

          sqlite3 = await WasmSqlite3.load(response.bodyBytes);
        }
      });

      test('get version', () {
        final version = sqlite3.version;
        expect(
          version,
          isA<Version>()
              .having((e) => e.libVersion, 'libVersion', startsWith('3.41')),
        );
      });

      test('can use current date', () {
        final db = sqlite3.openInMemory();
        addTearDown(db.dispose);

        final results =
            db.select("SELECT strftime('%s', CURRENT_TIMESTAMP) AS r");
        final row = results.single['r'] as String;

        expect(int.parse(row),
            closeTo(DateTime.now().millisecondsSinceEpoch ~/ 1000, 5));
      });
    });
  }
}
