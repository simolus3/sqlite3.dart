import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/src/hook/assets.dart';

import 'package:sqlite3/src/hook/description.dart';
import 'package:sqlite3/src/hook/openssl.dart';
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

        final downloaded = await sqlite.downloadIntoOutputDirectoryShared(
          input,
          output,
          library,
        );

        output.assets.code.add(
          CodeAsset(
            package: package,
            name: name,
            linkMode: DynamicLoadingBundled(),
            file: downloaded.uri,
          ),
        );
      case CompileSqlite(:final libraryType, :final sourceFile, :final defines):
        final targetOS = input.config.code.targetOS;

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
        if (targetOS == OS.linux && libraryType != LibraryType.sqlcipher) {
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

        final List<String> includes = [];
        final List<String> libraryDirectories = [];
        final List<String> libraries = [];
        final List<String> flags = [];

        if (libraryType == LibraryType.sqlcipher) {
          switch (targetOS) {
            case OS.macOS:
            case OS.iOS:
              // Link with CommonCrypto on Apple platforms, which is optimized
              flags.addAll([
                '-framework',
                'Foundation',
                '-framework',
                'Security',
              ]);
              break;
            case OS.android:
            case OS.linux:
            case OS.windows:
              // OpenSSL is downloaded next to the main source file
              final openSslSrcDir = Directory(
                p.join(File(sourceFile).parent.path, 'openssl-src'),
              );

              final openSslBinariesDir = (await buildOpenSSL(
                input,
                output,
                openSslSrcDir: openSslSrcDir,
              ))!;

              final cryptoStaticLib = File(
                getStaticCryptoLib(
                  openSslBinariesDir,
                  input.config.code.targetOS,
                  input.config.code.targetArchitecture,
                ),
              );

              includes.add(p.join(openSslBinariesDir.path, 'include'));
              libraryDirectories.add(cryptoStaticLib.parent.path);
              libraries.add('crypto');

              if (targetOS == OS.android) {
                // The android library is needed when linking
                libraries.add('log');
              }
            default:
              throw UnsupportedError(
                'Unsupported OS: ${input.config.code.targetOS}',
              );
          }
        }

        // final files = Directory(kOpenSSLBuiltDir).listSync();
        // print(files);

        final isMacLike = [OS.iOS, OS.macOS].contains(targetOS);

        final library = CBuilder.library(
          name: 'sqlite3',
          packageName: 'sqlite3',
          assetName: name,
          sources: [sourceFile],
          includes: [p.dirname(sourceFile), ...includes],
          defines: defines,
          flags: [
            if (input.config.code.targetOS == OS.linux) ...[
              if (linkerScript != null) ...[
                // This avoids loading issues on Linux, see comment above.
                '-Wl,-Bsymbolic',
                // And since we already have a designated list of symbols to
                // export, we might as well strip the rest.
                // TODO: Port this to other targets too.
                '-Wl,--version-script=$linkerScript',
              ],
              '-s',
              '-ffunction-sections',
              '-fdata-sections',
              '-Wl,--gc-sections',
            ],
            if (isMacLike) ...[
              '-headerpad_max_install_names',
              // clang would use the temporary directory passed by
              // native_toolchain_c otherwise. So this makes improves
              // reproducibility.
              '-install_name',
              '@rpath/libsqlite3.dylib',
            ],
            ...flags,
          ],
          libraryDirectories: [...libraryDirectories],
          libraries: [
            if (targetOS == OS.android || targetOS == OS.linux) ...[
              // We need to link the math library on Android.
              'm',
            ],
            ...libraries,
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
