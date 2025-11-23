import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

import 'package:sqlite3/src/hook/description.dart';
import 'package:sqlite3/src/hook/used_symbols.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final sqlite = SqliteBinary.forBuild(input);
    switch (sqlite) {
      case PrecompiledBinary():
        final library = sqlite.resolveLibrary(input.config.code);
        library.checkSupported();

        final dir = Directory(
          input.outputDirectoryShared.resolve(library.dirname).toFilePath(),
        );
        if (!dir.existsSync()) {
          dir.createSync();
        }

        final target = File(p.join(dir.path, library.filename));
        final tmp = File('${target.path}.tmp');

        await sqlite
            .fetch(input, output, library)
            .cast<List<int>>()
            .pipe(tmp.openWrite());
        tmp.renameSync(target.path);

        output.assets.code.add(
          CodeAsset(
            package: package,
            name: name,
            linkMode: DynamicLoadingBundled(),
            file: target.uri,
          ),
        );
      case CompileSqlite(:final sourceFile, :final defines):
        // With Flutter on Linux (which already dynamically links SQLite through
        // its libgtk dependency), we run into issues where loading our SQLite
        // build causes internal symbols to be resolved against the already
        // loaded library from the system.
        // This is terrible and not what we ever want. A proper solution may be
        // to use namespaces or RTLD_DEEPBIND, but hooks don't support that yet.
        // An alternative that seems to work is to pass -Bsymbolic-functions to
        // the linker.
        // For the full discussion, see https://github.com/dart-lang/native/issues/2724

        String? linkerScript;
        if (input.config.code.targetOS == OS.linux) {
          linkerScript = input.outputDirectory.resolve('sqlite.map').path;

          await File(linkerScript).writeAsString('''
{
  global:
${usedSqliteSymbols.map((symbol) => '    $symbol;').join('\n')}
  local:
    *;
};
''');
        }

        final library = CBuilder.library(
          name: 'sqlite3',
          packageName: 'sqlite3',
          assetName: name,
          sources: [sourceFile],
          includes: [p.dirname(sourceFile)],
          defines: defines,
          flags: [
            if (input.config.code.targetOS == OS.linux) ...[
              // This avoids loading issues on Linux, see comment above.
              '-Wl,-Bsymbolic',
              // And since we already have a designated list of symbols to
              // export, we might as well strip the rest.
              // TODO: Port this to other targets too.
              '-Wl,--version-script=$linkerScript',
              '-ffunction-sections',
              '-fdata-sections',
              '-Wl,--gc-sections',
            ],
            if (input.config.code.targetOS case OS.iOS || OS.macOS) ...[
              '-headerpad_max_install_names',
              // clang would use the temporary directory passed by
              // native_toolchain_c otherwise. So this makes improves
              // reproducibility.
              '-install_name',
              '@rpath/libsqlite3.dylib',
            ],
          ],
          libraries: [
            if (input.config.code.targetOS == OS.android)
              // We need to link the math library on Android.
              'm',
          ],
        );

        await library.run(input: input, output: output);
      case ExternalSqliteBinary():
        output.assets.code.add(
          CodeAsset(
            package: package,
            name: name,
            linkMode: sqlite.resolveLinkMode(input),
          ),
        );
    }
  });
}

const package = 'sqlite3';
const name = 'src/ffi/libsqlite3.g.dart';
