import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';

void main() async {
  Database openDatabase() {
    return sqlite3.openInMemory();
  }

  final pool = SqliteConnectionPool.open(
    name: 'test.db',
    openConnections: () => PoolConnections(openDatabase(), [
      for (var i = 0; i < 5; i++) openDatabase(),
    ]),
  );

  {
    final exclusive = await pool.exclusiveAccess();
    await exclusive.writer.execute('CREATE TEMPORARY TABLE conn(id);');
    await exclusive.writer.execute('INSERT INTO conn VALUES (?)', ['writer']);

    for (final (i, reader) in exclusive.readers.indexed) {
      await reader.execute('CREATE TEMPORARY TABLE conn(id);');
      await reader.execute('INSERT INTO conn VALUES (?)', ['reader-$i']);
    }
    exclusive.close();
  }

  pool.close();
}
