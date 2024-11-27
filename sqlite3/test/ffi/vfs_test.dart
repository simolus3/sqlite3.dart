@Tags(['ffi'])
library;

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../common/vfs.dart';

void main() {
  testVfs(() => sqlite3);
}
