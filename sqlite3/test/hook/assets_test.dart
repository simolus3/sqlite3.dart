@TestOn('vm')
library;

import 'package:code_assets/code_assets.dart';
import 'package:sqlite3/src/hook/assets.dart';
import 'package:test/test.dart';

void main() {
  test('prebuilt libraries have no conflicting dirname', () {
    final names = <String>{};
    for (final target in PrebuiltSqliteLibrary.all) {
      expect(
        names.add(target.dirname),
        isTrue,
        reason: 'dirname collision: ${target.dirname}',
      );
    }
  });

  test('dirname is deterministic (string-based, not Object.hash)', () {
    // If dirname were based on Object.hash(), these exact assertions would
    // fail in a different Dart process because Object.hash() uses a
    // per-isolate random seed. The fact that we can assert exact values
    // proves dirname is now stable across processes.
    final lib = PrebuiltSqliteLibrary(
      os: TargetOperatingSystem.android,
      architecture: Architecture.arm64,
      type: LibraryType.sqlite3,
    );
    expect(lib.dirname, 'download-sqlite3-3.3.3_sqlite3_android_arm64');
  });

  test('hashCode is volatile but dirname is stable', () {
    // Demonstrates the fix: hashCode (which uses Object.hash) changes
    // across Dart processes, so it must NOT be used for persistent names.
    // dirname uses deterministic string concatenation instead.
    final a = PrebuiltSqliteLibrary(
      os: TargetOperatingSystem.android,
      architecture: Architecture.arm64,
      type: LibraryType.sqlite3,
    );
    final b = PrebuiltSqliteLibrary(
      os: TargetOperatingSystem.android,
      architecture: Architecture.arm64,
      type: LibraryType.sqlite3,
    );

    // Equal libraries must have equal hashCode (within same process).
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));

    // Different configurations produce different dirnames.
    final c = PrebuiltSqliteLibrary(
      os: TargetOperatingSystem.ios,
      architecture: Architecture.arm64,
      type: LibraryType.sqlite3,
    );
    expect(c.dirname, isNot(equals(a.dirname)));
    expect(c.dirname, 'download-sqlite3-3.3.3_sqlite3_ios_arm64');
  });
}
