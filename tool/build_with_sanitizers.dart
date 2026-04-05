import 'dart:io';

import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

import 'package:sqlite3/src/hook/description.dart';
import '../sqlite3/hook/build.dart' as hook;

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

  for (final sanitizer in ['address', 'memory', 'thread']) {
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
            defines: CompilerDefines.defaults(false),
            flags: ['-fsanitize=$sanitizer'],
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
}

Uri _which(String tool) {
  final result = Process.runSync('which', [tool]);
  if (result.exitCode != 0) {
    throw 'Tool not found: $tool';
  }

  final path = (result.stdout as String).trim();
  return Uri.file(path);
}
