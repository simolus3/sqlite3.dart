@Tags(['ffi'])
library;

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/scaffolding.dart';

import '../common/database.dart';
import '../common/session.dart';

void main() {
  final hasColumnMeta =
      open.openSqlite().providesSymbol('sqlite3_column_table_name');
  final hasSession = open.openSqlite().providesSymbol('sqlite3session_create');

  testDatabase(() => sqlite3, hasColumnMetadata: hasColumnMeta);

  group('session', () {
    testSession(() => sqlite3);
  }, skip: hasSession ? false : 'Missing session extension');
}
