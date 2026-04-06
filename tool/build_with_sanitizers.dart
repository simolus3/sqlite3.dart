import 'dart:io';

import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import 'package:sqlite3/src/hook/description.dart';
import '../sqlite3/hook/build.dart' as hook;

final _limitConcurrency = Pool(Platform.numberOfProcessors);

/// Builds `libsqlite3.so` variants for X64 Linux with different sanitizers
/// enabled.
void main() async {
  const fs = LocalFileSystem();
  Directory.current = Directory('sqlite3');

  final sourcePath = fs.currentDirectory.parent
      .childDirectory('sqlite-src')
      .childDirectory('sqlite3')
      .childFile('sqlite3.c')
      .path;

  final outputDirectory =
      fs.currentDirectory.parent.childDirectory('sqlite-sanitized');
  if (await outputDirectory.exists()) {
    await outputDirectory.delete(recursive: true);
  }
  await outputDirectory.create();

  Future<void> compileWithSanitizer(String sanitizer) async {
    await testBuildHook(
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.x64,
          targetOS: OS.linux,
          linkModePreference: LinkModePreference.dynamic,
          cCompiler: CCompilerConfig(
            archiver: _which('llvm-ar'),
            compiler: _which('clang'),
            linker: _which('lld'),
          ),
        )
      ],
      linkingEnabled: true,
      mainMethod: (args) {
        return build(args, (input, output) async {
          final sourceFile =
              p.relative(sourcePath, from: fs.currentDirectory.path);
          final library = CBuilder.library(
            name: 'sqlite3',
            packageName: 'sqlite3',
            assetName: hook.name,
            sources: [sourceFile],
            includes: [p.dirname(sourceFile)],
            defines: {
              'SQLITE_ENABLE_API_ARMOR': '1',
              ...CompilerDefines.defaults(false),
            },
            flags: [
              '-fsanitize=$sanitizer',
              '-fno-omit-frame-pointer',
              // It looks like os calls like stat() don't count as initializing
              // memory, so we have to exclude SQLite itself from msan tests.
              // But we can already assume it to be correct, we mainly want to
              // test Dart parts.
              if (sanitizer == 'memory')
                '-fsanitize-ignorelist=../native_tests/ignorelist.txt'
            ],
          );

          await library.run(input: input, output: output);
        });
      },
      check: (_, output) async {
        final name = 'sqlite3.san_$sanitizer.so';
        for (final file in output.assets.code) {
          await fs.file(file.file!).copy(outputDirectory.childFile(name).path);
        }
      },
    );
  }

  await [
    for (final sanitizer in ['address', 'memory', 'thread'])
      _limitConcurrency.withResource(() => compileWithSanitizer(sanitizer)),
  ].wait;
}

Uri _which(String tool) {
  final result = Process.runSync('which', [tool]);
  if (result.exitCode != 0) {
    throw 'Tool not found: $tool';
  }

  final path = (result.stdout as String).trim();
  return Uri.file(path);
}
