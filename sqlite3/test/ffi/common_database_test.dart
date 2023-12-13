@Tags(['ffi'])
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/ffi/bindings.dart';
import 'package:test/scaffolding.dart';

import '../common/database.dart';

void main() {
  testDatabase(
    () => sqlite3,
    hasColumnMetadata: SupportedSqliteFeatures.features.supportsColumnMetadata,
  );
}
