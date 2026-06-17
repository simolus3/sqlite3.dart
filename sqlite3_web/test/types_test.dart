import 'package:sqlite3_web/types.dart';
import 'package:test/test.dart';

void main() {
  test('can import types.dart library outside of the web', () {
    // The only purpose of this test is to ensure that
    // package:sqlite3_web/types.dart can be imported on native targets.
    DatabaseImplementation.values;
  });
}
