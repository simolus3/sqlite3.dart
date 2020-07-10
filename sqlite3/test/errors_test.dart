import 'dart:io';

import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('open read-only exception', () async {
    final path =
        join('.dart_tool', 'sqlite3', 'test', 'read_only_exception.db');

    try {
      await Directory(dirname(path)).create(recursive: true);
    } catch (_) {}
    // but not the db
    try {
      await File(path).delete();
    } catch (_) {}

    // Opening a non-existent database should fail
    try {
      sqlite3.open(path, mode: OpenMode.readOnly);
      fail('should fail');
    } on SqliteException catch (e) {
      expect(e.extendedResultCode, 14);
      expect(e.toString(), startsWith('SqliteException(14): '));
    }
  });

  test('statement exception', () async {
    final db = sqlite3.openInMemory();

    // Basic syntax error
    try {
      db.execute('DUMMY');
      fail('should fail');
    } on SqliteException catch (e) {
      expect(e.extendedResultCode, 1);
      expect(e.resultCode, 1);
      expect(e.toString(), startsWith('SqliteException(1): '));
    }

    // No table
    try {
      db.execute('SELECT * FROM missing_table');
      fail('should fail');
    } on SqliteException catch (e) {
      expect(e.extendedResultCode, 1);
      expect(e.resultCode, 1);
    }

    // Constraint primary key
    db.execute('CREATE TABLE Test (name TEXT PRIMARY KEY)');
    db.execute("INSERT INTO Test(name) VALUES('test1')");
    try {
      db.execute("INSERT INTO Test(name) VALUES('test1')");
      fail('should fail');
    } on SqliteException catch (e) {
      // SQLITE_CONSTRAINT_PRIMARYKEY (1555)
      expect(e.extendedResultCode, 1555);
      expect(e.resultCode, 19);
      expect(e.toString(), startsWith('SqliteException(1555): '));
    }

    // Constraint using prepared statement
    db.execute('CREATE TABLE Test2 (id PRIMARY KEY, name TEXT UNIQUE)');
    final prepared = db.prepare('INSERT INTO Test2(name) VALUES(?)');
    prepared.execute(['test2']);
    try {
      prepared.execute(['test2']);
      fail('should fail');
    } on SqliteException catch (e) {
      // SQLITE_CONSTRAINT_UNIQUE (2067)
      expect(e.extendedResultCode, 2067);
      expect(e.resultCode, 19);
    }
    db.dispose();
  });

  test('busy exception', () async {
    final path = join('.dart_tool', 'moor_ffi', 'test', 'busy.db');
    // Make sure the path exists
    try {
      await Directory(dirname(path)).create(recursive: true);
    } catch (_) {}
    // but not the db
    try {
      await File(path).delete();
    } catch (_) {}

    final db1 = sqlite3.open(path);
    final db2 = sqlite3.open(path);
    db1.execute('BEGIN EXCLUSIVE TRANSACTION');
    try {
      db2.execute('BEGIN EXCLUSIVE TRANSACTION');
      fail('should fail');
    } on SqliteException catch (e) {
      expect(e.extendedResultCode, 5);
      expect(e.resultCode, 5);
    }
    db1.dispose();
    db2.dispose();
  });

  test('invalid format', () async {
    final path = join('.dart_tool', 'moor_ffi', 'test', 'invalid_format.db');
    // Make sure the path exists
    try {
      await Directory(dirname(path)).create(recursive: true);
    } catch (_) {}
    await File(path).writeAsString('not a database file');

    final db = sqlite3.open(path);
    try {
      db.userVersion = 1;
      fail('should fail');
    } on SqliteException catch (e) {
      expect(e.extendedResultCode, 26);
      expect(e.resultCode, 26);
    }
    db.dispose();
  });
}
