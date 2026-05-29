// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('can open sqlite3', () {
    print(sqlite3.version);

    final db = sqlite3.openInMemory()..closeWhenDone();
    print(db.select('pragma compile_options'));
  });

  test('pool smoke test', () async {
    final pool = SqliteConnectionPool.open(
      name: 'test-pool',
      openConnections: () => PoolConnections(sqlite3.openInMemory(), []),
    );

    pool.execute('CREATE TABLE foo (bar TEXT)');
    pool.close();
  });

  test('can open databases', () {
    final db = sqlite3.openInMemory()
      ..closeWhenDone()
      ..execute('CREATE TABLE foo (bar)')
      ..execute('INSERT INTO foo VALUES (1), (2)');

    expect(db.select('SELECT * FROM foo'), [
      {'bar': 1},
      {'bar': 2},
    ]);
  });

  test('has json support', () {
    final db = sqlite3.openInMemory()..closeWhenDone();
    expect(db.select("SELECT json('[1,  2, 3]') AS r;"), [
      {'r': '[1,2,3]'},
    ]);
  });

  test('has fts5 support', () {
    final db = sqlite3.openInMemory()..closeWhenDone();

    db.execute('CREATE VIRTUAL TABLE foo USING fts5 (a,b,c);');
  });

  test('can create collation', () {
    final db = sqlite3.openInMemory()
      ..closeWhenDone()
      ..execute('CREATE TABLE foo2 (bar)')
      ..execute(
        "INSERT INTO foo2 VALUES ('AaAaaaAA'), ('BBBbBb'),('cCCCcc    '), ('  dD   ')",
      );

    /// Create a collation to compare String without extra-blank to the right and
    /// ignoring case
    db.createCollation(
      name: "RTRIMNOCASE",
      function: (String? a, String? b) {
        // Combining nocase and rtrim
        //
        String? compareA = a?.toLowerCase().trimRight();
        String? compareB = b?.toLowerCase().trimRight();

        if (compareA == null && compareB == null) {
          return 0;
        } else if (compareA == null) {
          // a < b
          return -1;
        } else if (compareB == null) {
          // a > b
          return 1;
        } else {
          return compareA.compareTo(compareB);
        }
      },
    );

    expect(
      db.select(
        "SELECT * FROM foo2 WHERE bar = 'aaaaAaAa   ' COLLATE RTRIMNOCASE",
      ),
      [
        {'bar': 'AaAaaaAA'},
      ],
    );

    expect(
      db.select("SELECT * FROM foo2 WHERE bar = 'bbbbbb' COLLATE RTRIMNOCASE"),
      [
        {'bar': 'BBBbBb'},
      ],
    );

    expect(
      db.select("SELECT * FROM foo2 WHERE bar = 'cCcccC' COLLATE RTRIMNOCASE"),
      [
        {'bar': 'cCCCcc    '},
      ],
    );

    expect(
      db.select("SELECT * FROM foo2 WHERE bar = 'dd' COLLATE RTRIMNOCASE"),
      [],
    );
  });

  const ciphers = bool.fromEnvironment('sqlite3.multipleciphers');
  if (ciphers) {
    test('contains sqlite3multipleciphers', () {
      final db = sqlite3.openInMemory()..closeWhenDone();
      print(db.select('select sqlite3mc_config(?)', ['cipher']));
    });
  }

  const sqlcipher = bool.fromEnvironment('sqlite3.sqlcipher');
  if (sqlcipher) {
    test('cipher_version', () {
      final db = sqlite3.openInMemory()..closeWhenDone();
      final cipherVersionRows = db.select('PRAGMA cipher_version');
      print(cipherVersionRows);
      expect(cipherVersionRows, isNotEmpty);
    });
  }

  if (ciphers || sqlcipher) {
    test('encryption', () {
      final dir = Directory.systemTemp.createTempSync();
      final path = join(dir.path, 'test.db');
      final db = sqlite3.open(path);
      addTearDown(() {
        db.close();
      });

      final key = 'my_secret';
      db.execute("PRAGMA key = '$key'");
      db.execute("CREATE TABLE users (id INTEGER, username TEXT)");
      db.close();

      final dbAfterEnc = sqlite3.open(path);
      addTearDown(() => dbAfterEnc.close());
      expect(
        () => dbAfterEnc.select('SELECT * FROM sqlite_master'),
        throwsSqlError(SqlError.SQLITE_NOTADB, SqlError.SQLITE_NOTADB),
      );
      dbAfterEnc.execute("PRAGMA key = '$key'");

      // Reads the db after setting the key
      expect(dbAfterEnc.select('SELECT * FROM sqlite_master'), isNotEmpty);
    });
  }
}

void testEncryptAndOpenEncrypted() {}

Matcher throwsSqlError(int resultCode, int extendedResultCode) {
  return throwsA(
    isA<SqliteException>()
        .having(
          (e) => e.extendedResultCode,
          'extendedResultCode',
          extendedResultCode,
        )
        .having((e) => e.resultCode, 'resultCode', resultCode),
  );
}

extension on Database {
  void closeWhenDone() => addTearDown(close);
}
