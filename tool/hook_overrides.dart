import 'dart:io';

/// Adds a `hooks` section to the `pubspec.yaml` of the directory the script is
/// running in to customize how `package:sqlite3` loads `libsqlite3`.
void main() async {
  final out = await File('pubspec.yaml').openWrite(mode: FileMode.append);
  out.write('''
hooks:
  user_defines:
    sqlite3:
      source: test-sqlite3
      directory: sqlite/out/
''');

  await out.flush();
  await out.close();
}
