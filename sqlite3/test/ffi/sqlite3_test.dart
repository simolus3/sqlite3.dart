@Tags(['ffi'])
library;

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
        ..close();
    } finally {
      sqlite3.tempDirectory = old;
    }
  });

  test(
    'can load extensions',
    () async {
      final sourcePath = p.join(d.sandbox, 'test_extension.c');
      final String dynamicLibraryPath;
      final ProcessResult result;

      await File(sourcePath).writeAsString('''
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1

static void my_function(sqlite3_context* context, int argc,
                        sqlite3_value** argv) {
  sqlite3_result_text(context, "my custom extension", -1, SQLITE_STATIC);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_myextension_init(sqlite3* db, char** pzErrMsg,
                             const sqlite3_api_routines* pApi) {
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);

  rc = sqlite3_create_function(
      db, "my_function", 0,
      SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC, 0, my_function, 0,
      0);

  return rc;
}
''');

      // https://www.sqlite.org/loadext.html#compiling_a_loadable_extension
      if (Platform.isLinux) {
        dynamicLibraryPath = p.join(d.sandbox, 'libmy_extension.so');

        result = await Process.run('gcc', [
          '-fpic',
          '-shared',
          sourcePath,
          '-o',
          dynamicLibraryPath,
        ]);
      } else if (Platform.isWindows) {
        dynamicLibraryPath = p.join(d.sandbox, 'my_extension.dll');

        result = await Process.run('cl', [
          sourcePath,
          '/link',
          '/DLL',
          '/OUT:$dynamicLibraryPath',
        ]);
      } else if (Platform.isMacOS) {
        dynamicLibraryPath = p.join(d.sandbox, 'my_extension.dylib');

        result = await Process.run('gcc', [
          '-fpic',
          '-dynamiclib',
          sourcePath,
          '-o',
          dynamicLibraryPath,
        ]);
      } else {
        fail('Test should not run on this platform');
      }

      if (result.exitCode != 0) {
        fail(
          'Could not compile shared library for extension: \n'
          '${result.stderr}\n${result.stdout}',
        );
      }

      final library = DynamicLibrary.open(dynamicLibraryPath);
      sqlite3.ensureExtensionLoaded(
        SqliteExtension.inLibrary(library, 'sqlite3_myextension_init'),
      );

      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(db.select('SELECT my_function() AS r'), [
        {'r': 'my custom extension'},
      ]);
    },
    tags: 'ci_only',
    onPlatform: const <String, Skip>{
      // todo: Ideally we should also test this on macOS, but the extension
      // doesn't seem to compile with the default includes on this system.
      // Windows also doesn't seem to work, but I think my poor GitHub actions
      // setup is to blame for that
      '!linux': Skip('Unsupported platform'),
    },
  );
}
