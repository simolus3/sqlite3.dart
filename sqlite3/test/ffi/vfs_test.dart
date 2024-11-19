import 'package:sqlite3/sqlite3.dart';

import '../common/vfs.dart';

void main() {
  testVfs(() => sqlite3);
}
