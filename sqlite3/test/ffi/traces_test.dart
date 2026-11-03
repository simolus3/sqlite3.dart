@Tags(['ffi'])
library;

import 'package:sqlite3/sqlite3.dart';
import 'package:test/scaffolding.dart';

import '../common/traces.dart';

void main() {
  final supportsTraces = _supportsTraces();

  group(
    'traces',
    () => testTraces(() => sqlite3),
    skip: supportsTraces ? false : 'sqlite3 library does not support tracing',
  );
}

bool _supportsTraces() {
  final database = sqlite3.openInMemory();
  try {
    database.trace = SqliteTraceCallback((_) => 0);
    database.trace = null;
    return true;
  } on UnsupportedError {
    return false;
  } finally {
    database.close();
  }
}
