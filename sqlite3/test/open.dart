import 'package:sqlite3/default_open.dart';
import 'package:sqlite3/sqlite3.dart';

Sqlite3 _instance;
Sqlite3 open() {
  return _instance ??= defaultOpen();
}
