import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.open('example.db');
  print(db.select("pragma cipher = 'sqlcipher'"));
  print(db.select('pragma legacy = 4'));

  print(db.select("pragma key = 'foo'"));
  print(db.select('SELECT * FROM foo;'));
}
