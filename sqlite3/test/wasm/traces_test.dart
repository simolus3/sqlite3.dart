@Tags(['wasm'])
library;

import 'package:test/scaffolding.dart';

import '../common/traces.dart';
import 'utils.dart';

void main() {
  testTraces(loadSqlite3);
}
