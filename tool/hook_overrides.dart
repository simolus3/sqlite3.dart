import 'dart:io';

import 'package:path/path.dart' as p;

/// Adds a `hooks` section to the `pubspec.yaml` of the directory the script is
/// running in to customize how `package:sqlite3` loads `libsqlite3`.
void main(List<String> args) async {
  for (final path in ['pubspec.yaml', 'examples/pubspec.yaml']) {
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
      case 'compiled':
        final outPath = p.relative('sqlite-compiled', from: p.dirname(path));

        out.write('''
hooks:
  user_defines:
    sqlite3:
      source: test-sqlite3
      directory: $outPath/
''');
    }

    await out.flush();
    await out.close();
  }
}
