import 'dart:io';

import 'package:path/path.dart' as p;

/// Adds a `hooks` section to the `pubspec.yaml` of the directory the script is
/// running in to customize how `package:sqlite3` loads `libsqlite3`.
void main(List<String> args) async {
  for (final path in ['pubspec.yaml', 'examples/pubspec.yaml']) {
    Process.runSync('git', ['restore', '--', path]);

    final out = await File(path).openWrite(mode: FileMode.append);
    final [mode] = args;
    switch (mode) {
      case 'system':
        out.write('''
hooks:
  user_defines:
    sqlite3:
      source: system
''');
      case 'system-os-specific':
        out.write('''
hooks:
  user_defines:
    sqlite3:
      source: system
      name_linux: sqlite3
      name_macos: sqlite3
      name_windows: winsqlite3
      name: bogus_value_to_fail_if_selected
''');
      case 'compiled':
        final outPath = p.relative('sqlite-compiled', from: p.dirname(path));

        out.write('''
hooks:
  user_defines:
    sqlite3:
      source: test-sqlite3
      directory: $outPath/
''');
      case 'compiled-ciphers':
        final outPath = p.relative('sqlite-compiled', from: p.dirname(path));

        out.write('''
hooks:
  user_defines:
    sqlite3:
      source: test-sqlite3mc
      directory: $outPath/
''');
      default:
        throw 'Unsupported mode, can use system, system-os-specific, '
            'compiled, compiled-ciphers';
    }

    await out.flush();
    await out.close();
  }
}
