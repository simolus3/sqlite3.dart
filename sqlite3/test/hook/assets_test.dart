@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/src/hook/assets.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  test('prebuilt libraries have no conflicting hash code', () {
    // We join the hash code against the outputDirectoryShared of hooks, so
    // there should be no collisions.
    final hashes = <String>{};
    for (final target in PrebuiltSqliteLibrary.all) {
      expect(hashes.add(target.dirname), isTrue);
    }
  });

  test('hash codes are stable', () async {
    final process = await Process.run(Platform.resolvedExecutable, [
      join('test', 'hook', 'print_asset_dirnames.dart'),
    ]);
    if (process.exitCode != 0) {
      fail(
        'Could not run print_asset_dirnames.dart (exit code ${process.exitCode}): ${process.stderr}',
      );
    }

    final dirnames = process.stdout as String;
    final expected = PrebuiltSqliteLibrary.all
        .map((e) => '${e.dirname}${Platform.lineTerminator}')
        .join();
    expect(dirnames, expected);
  });
}
