@Tags(['wasm'])
import 'package:test/test.dart';

import '../common/database.dart';
import 'utils.dart';

void main() {
  testDatabase(loadSqlite3);
}
