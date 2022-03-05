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
          .having((e) => e.libVersion, 'libVersion', startsWith('3.38')),
    );
  });
}
