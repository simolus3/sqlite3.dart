import 'package:test/test.dart';

import 'open.dart';

void main() {
  test('version', () {
    final version = open().version;
    expect(version, isNotNull);
  });
}
