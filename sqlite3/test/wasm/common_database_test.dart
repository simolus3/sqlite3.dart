@Tags(['wasm'])
library;

import 'package:test/test.dart';

import '../common/database.dart';
import '../common/session.dart';
import 'utils.dart';

void main() {
  testDatabase(loadSqlite3);
  group('session', () {
    testSession(loadSqlite3);
  });
}
