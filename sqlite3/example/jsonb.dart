import 'package:sqlite3/sqlite3.dart';

void main() {
  final database = sqlite3.openInMemory()
    ..execute('CREATE TABLE entries (entry BLOB NOT NULL) STRICT;')
    // You can insert JSONB-formatted values directly
    ..execute('INSERT INTO entries (entry) VALUES (?)', [
      jsonb.encode({'hello': 'dart'})
    ]);
  // And use them with JSON operators in SQLite without a further conversion:
  print(database.select('SELECT entry ->> ? AS r FROM entries;', [r'$.hello']));
}
