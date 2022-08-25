@Tags(['ffi'])
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  test('get version', () {
    final version = sqlite3.version;
    expect(version, isNotNull);
  });

  test('sqlite3_temp_directory', () {
    final dir = Directory(d.path('sqlite3/tmp'));
    dir.createSync(recursive: true);
    final old = sqlite3.tempDirectory;

    try {
      sqlite3.tempDirectory = dir.absolute.path;

      final db = sqlite3.open(d.path('tmp.db'));
      db
        ..execute('PRAGMA temp_store = FILE;')
        ..execute('CREATE TEMP TABLE my_tbl (foo, bar);')
        ..userVersion = 3
        ..dispose();
    } finally {
      sqlite3.tempDirectory = old;
    }
  });
}
