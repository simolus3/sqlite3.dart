@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';
import 'package:typed_data/typed_data.dart';

import 'utils.dart';

void main() {
  test('can open databases with sqlite3mc', () async {
    final sqlite3 = await loadSqlite3WithoutVfs(encryption: true);
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(name: 'dart-mem'));

    sqlite3.open('/test', vfs: 'multipleciphers-dart-mem')
      ..execute('pragma key = "key"')
      ..execute('CREATE TABLE foo (bar TEXT) STRICT;')
      ..execute('INSERT INTO foo VALUES (?)', ['test'])
      ..close();

    final database = sqlite3.open('/test', vfs: 'multipleciphers-dart-mem');
    expect(
      () => database.select('SELECT * FROM foo'),
      throwsA(
        isA<SqliteException>().having(
          (e) => e.message,
          'message',
          contains('not a database'),
        ),
      ),
    );

    database.execute('pragma key = "key"');
    expect(database.select('SELECT * FROM foo'), isNotEmpty);
  });

  test('can encrypt and decrypt databases', () async {
    final regular = await loadSqlite3WithoutVfs(encryption: false);
    final ciphers = await loadSqlite3WithoutVfs(encryption: true);

    final memory = InMemoryFileSystem();
    regular.registerVirtualFileSystem(memory);

    {
      final db = regular.open('/app.db', vfs: memory.name);
      db.execute('create table foo (bar text);');
      db.close();
    }

    // Replace with encrypted copy.
    memory.fileData['/app.db'] = Uint8Buffer()
      ..addAll(
        _encryptDatabase(
          ciphers,
          memory.fileData['/app.db']!.buffer.asUint8List(),
          'encryption key',
        ),
      );

    // Which should now be impossible to open
    {
      final db = regular.open('/app.db', vfs: memory.name);
      expect(
        () => db.select('SELECT * FROM sqlite_schema'),
        throwsA(isA<SqliteException>()),
      );

      db.close();
    }

    // Replace with decrypted database
    memory.fileData['/app.db'] = Uint8Buffer()
      ..addAll(
        _decryptDatabase(
          ciphers,
          memory.fileData['/app.db']!.buffer.asUint8List(),
          'encryption key',
        ),
      );

    // Which we should be able to open again
    {
      final db = regular.open('/app.db', vfs: memory.name);
      expect(db.select('SELECT * FROM sqlite_schema'), hasLength(1));

      db.close();
    }
  });
}

Uint8List _encryptDatabase(
  WasmSqlite3 bindings,
  Uint8List decrypted,
  String key,
) {
  final vfs = InMemoryFileSystem(name: 'encrypt');
  vfs.fileData['/app.db'] = Uint8Buffer()..addAll(decrypted);
  bindings.registerVirtualFileSystem(vfs);

  final db = bindings.open('/app.db', vfs: 'multipleciphers-${vfs.name}');
  db.execute("pragma rekey ='${key.replaceAll("'", "''")}'");
  db.close();
  bindings.unregisterVirtualFileSystem(vfs);

  final data = vfs.fileData['/app.db']!;
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Uint8List _decryptDatabase(
  WasmSqlite3 bindings,
  Uint8List decrypted,
  String key,
) {
  final vfs = InMemoryFileSystem(name: 'decrypt');
  vfs.fileData['/app.db'] = Uint8Buffer()..addAll(decrypted);
  bindings.registerVirtualFileSystem(vfs);

  final db = bindings.open('/app.db', vfs: 'multipleciphers-${vfs.name}');
  db.execute("pragma key ='${key.replaceAll("'", "''")}'");
  db.execute("pragma rekey = ''");
  db.close();
  bindings.unregisterVirtualFileSystem(vfs);

  final data = vfs.fileData['/app.db']!;
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
