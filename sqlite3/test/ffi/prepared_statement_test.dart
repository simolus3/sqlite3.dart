@Tags(['ffi'])
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../common/prepared_statement.dart';

void main() {
  final version = sqlite3.version;
  final hasReturning = version.versionNumber > 3035000;

  testPreparedStatements(() => sqlite3, supportsReturning: hasReturning);
}
