import 'package:sqlite3/src/hook/assets.dart';

// Spawned as a subprocess from assets_test.dart to verify hashes are consistent
// across Dart runs. See https://github.com/simolus3/sqlite3.dart/pull/384 for
// details.
void main() {
  for (final target in PrebuiltSqliteLibrary.all) {
    print(target.dirname);
  }
}
