import 'dart:convert';
import 'dart:io';

/// Appends hook user-defines to `sqlite3_native_assets`, configuring it to use
/// a downloaded SQLite source instead of downloading it itself.
///
/// This ensures we're not downloading SQLite over and over again when running
/// the CI steps.
void main() async {
  final sink = File('pubspec.yaml').openWrite(mode: FileMode.append);
  sink.add(utf8.encode('''

hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        local: sqlite/out/sqlite3.c

'''));
  await sink.flush();
  await sink.close();
}
