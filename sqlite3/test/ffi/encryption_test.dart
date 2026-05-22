@Tags(['ffi'])
library;

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/hook/assets.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../common/utils.dart';

void main() {
  test('encryption', () {
    final LibraryType libraryType = _inferLibraryType();

    if (libraryType == LibraryType.sqlcipher ||
        libraryType == LibraryType.sqlite3mc) {
      testEncryptAndOpenEncrypted();
    }
  });
}

void testEncryptAndOpenEncrypted() {
  final path = d.path('test.db');
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
}

LibraryType _inferLibraryType() {
  final db = sqlite3.openInMemory();

  try {
    // Sqlcipher can check PRAGMA cipher_version
    final cipherVersionRows = db.select('PRAGMA cipher_version');
    if (cipherVersionRows.isNotEmpty) {
      return LibraryType.sqlcipher;
    }

    // PRAGMA cipher is available in sqlite3mc
    final cipherRows = db.select('PRAGMA cipher');
    if (cipherRows.isNotEmpty) {
      return LibraryType.sqlite3mc;
    }

    return LibraryType.sqlite3;
  } finally {
    db.close();
  }
}
