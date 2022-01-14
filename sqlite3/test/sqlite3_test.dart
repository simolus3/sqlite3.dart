import 'dart:io';

import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('get version', () {
    final version = sqlite3.version;
    expect(version, isNotNull);
  });

  test('sqlite3_temp_directory', () {
    final newTempPath = Directory.systemTemp.path;
    final old = sqlite3.tempDirectory;

    try {
      sqlite3.tempDirectory = newTempPath;

      final db = sqlite3.open(join(newTempPath, 'tmp.db'));
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
