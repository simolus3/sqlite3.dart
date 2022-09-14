@Tags(['ffi'])
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  test('get version', () {
    final version = sqlite3.version;
    expect(version, isNotNull);
  });

  test('sqlite3_temp_directory', () {
    final dir = Directory(d.path('sqlite3/tmp'));
    dir.createSync(recursive: true);
    final old = sqlite3.tempDirectory;

    try {
      sqlite3.tempDirectory = dir.absolute.path;

      final db = sqlite3.open(d.path('tmp.db'));
      db
        ..execute('PRAGMA temp_store = FILE;')
        ..execute('CREATE TEMP TABLE my_tbl (foo, bar);')
        ..userVersion = 3
        ..dispose();
    } finally {
      sqlite3.tempDirectory = old;
    }
  });

  test(
    'can load extensions',
    () async {
      const sourcePath = 'test/ffi/test_extension.c';
      final String dynamicLibraryPath;

      // https://www.sqlite.org/loadext.html#compiling_a_loadable_extension
      if (Platform.isLinux) {
        dynamicLibraryPath = p.join(d.sandbox, 'libmy_extension.so');

        await Process.run('gcc', [
          '-fpic',
          '-shared',
          sourcePath,
          '-o',
          dynamicLibraryPath,
        ]);
      } else if (Platform.isWindows) {
        dynamicLibraryPath = p.join(d.sandbox, 'my_extension.dll');

        await Process.run(
            'cl', [sourcePath, '-link', '-dll', '-out:$dynamicLibraryPath']);
      } else if (Platform.isMacOS) {
        dynamicLibraryPath = p.join(d.sandbox, 'my_extension.dylib');

        await Process.run('gcc', [
          '-fpic',
          '-dynamiclib',
          sourcePath,
          '-o',
          dynamicLibraryPath,
        ]);
      } else {
        fail('Test should not run on this platform');
      }

      final library = DynamicLibrary.open(dynamicLibraryPath);
      sqlite3.ensureExtensionLoaded(
          SqliteExtension.inLibrary(library, 'sqlite3_myextension_init'));

      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      expect(db.select('SELECT my_function() AS r'), [
        {'r': 'my custom extension'},
      ]);
    },
    tags: 'ci_only',
    onPlatform: const <String, Skip>{
      '!windows && !linux && !mac-os': Skip('Unsupported platform'),
    },
  );
}
