@Tags(['ffi', 'ci_only'])
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  test(
    'can load dynamic extensions',
    () async {
      const sourcePath = 'assets/tests/my_extension.c';
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
        throw AssertionError('Test should not run on this platform');
      }

      final db = sqlite3.openInMemory()..loadExtension(dynamicLibraryPath);

      expect(db.select('SELECT my_function() AS r'), [
        {'r': 'my custom extension'},
      ]);
    },
    onPlatform: const <String, Skip>{
      '!windows && !linux && !mac-os': Skip('Unsupported platform'),
    },
  );
}
