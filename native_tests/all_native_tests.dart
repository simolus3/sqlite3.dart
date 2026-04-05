import 'package:test/test.dart';

import '../sqlite3/test/ffi/common_database_test.dart' as common_database_test;
import '../sqlite3/test/ffi/database_test.dart' as database_test;
import '../sqlite3/test/ffi/ffi_test.dart' as ffi_test;
import '../sqlite3/test/ffi/prepared_statement_test.dart'
    as prepared_statement_test;
import '../sqlite3/test/ffi/sqlite3_test.dart' as sqlite3_test;
import '../sqlite3/test/ffi/vfs_test.dart' as vfs_test;

import '../sqlite3_connection_pool/test/pool_test.dart' as pool_test;

import '../sqlite3_test/test/sqlite3_test_test.dart' as sqlite3_test_test;

/// Runs all native tests.
///
/// We aot-compile this file to run tests with different sanitizers.
void main() {
  group('package:sqlite3', () {
    group('common_database_test.dart', common_database_test.main);
    group('database_test.dart', database_test.main);
    group('ffi_test.dart', ffi_test.main);
    group('prepared_statement_test.dart', prepared_statement_test.main);
    group('sqlite3_test.dart', sqlite3_test.main);
    group('vfs_test.dart', vfs_test.main);
  });

  group('package:sqlite3_connection_pool', () {
    pool_test.main();
  });

  group('package:sqlite3_test', () {
    sqlite3_test_test.main();
  });
}
