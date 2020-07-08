import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('version', () {
    final version = sqlite3.version;
    expect(version, isNotNull);
  });
}
