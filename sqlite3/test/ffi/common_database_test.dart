@Tags(['ffi'])
library;

import 'package:sqlite3/sqlite3.dart';
import 'package:test/scaffolding.dart';

import '../common/database.dart';
import '../common/session.dart';

void main() {
  final hasColumnMeta = sqlite3.usedCompileOption('ENABLE_COLUMN_METADATA');
  final hasSession = sqlite3.usedCompileOption('ENABLE_SESSION');
  final hasSharedCache = !sqlite3.usedCompileOption('OMIT_SHARED_CACHE');

  testDatabase(
    () => sqlite3,
    hasColumnMetadata: hasColumnMeta,
    hasSharedCache: hasSharedCache,
  );

  group('session', () {
    testSession(() => sqlite3);
  }, skip: hasSession ? false : 'Missing session extension');
}
