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

        final isSqlcipher = input.userDefines['is_sqlcipher'] as bool? ?? false;

        final targetOS = input.config.code.targetOS;
        final targetArchitecture = input.config.code.targetArchitecture;
        final isAppleTarget = targetOS == OS.iOS || targetOS == OS.macOS;

        // Directory where the architecture compiled OpenSSL is located. Null if OpenSSL is not used
        Directory? openSslCompileDir;
        File? openSslStaticLib;
        if (isSqlcipher) {
          final linksWithOpenSSL =
              targetOS == OS.android ||
              targetOS == OS.linux ||
              targetOS == OS.windows;
          if (linksWithOpenSSL) {
            const openSSLCompiledRootKey = 'openssl_compiled_root';
            final Uri? opensslCompiledRoot = input.userDefines.path(
              openSSLCompiledRootKey,
            );

            if (opensslCompiledRoot == null) {
              throw StateError(
                'Target $targetOS needs OpenSSL compiled dir root with \'openSSLCompiledRootKey\'',
              );
            }

            openSslCompileDir = Directory(
              p.join(
                opensslCompiledRoot.toFilePath(),
                "${targetOS.name}-${targetArchitecture.name}",
              ),
            );

            if (!await openSslCompileDir.exists()) {
              throw StateError(
                'Expected OpenSSL compiled directory at ${openSslCompileDir.path}',
              );
            }

            openSslStaticLib = File(
              p.join(
                openSslCompileDir.path,
                _getOpenSslLibFolderName(targetOS, targetArchitecture),
                targetOS.staticlibFileName(
                  // OpenSSL builds include the lib prefix even on Windows, but
                  // staticlibFileName doesn't.
                  targetOS == OS.windows ? 'libcrypto' : 'crypto',
                ),
              ),
            );

            if (!await openSslStaticLib.exists()) {
              throw StateError(
                'Expected OpenSSL static library at ${openSslStaticLib.path}',
              );
            }
          }
        }

        final library = CBuilder.library(
          name: 'sqlite3',
          packageName: 'sqlite3',
          assetName: name,
          sources: [sourceFile],
          includes: [
            p.dirname(sourceFile),
            if (openSslCompileDir != null)
              p.join(openSslCompileDir.path, 'include'),
          ],
          defines: defines,
          flags: [
            if (input.config.code.targetOS == OS.linux) ...[
              // This avoids loading issues on Linux, see comment above.
              '-Wl,-Bsymbolic',
              // And since we already have a designated list of symbols to
              // export, we might as well strip the rest.
              // TODO: Port this to other targets too.
              '-Wl,--version-script=$linkerScript',
              // Strip symbols
              '-s',
              '-ffunction-sections',
              '-fdata-sections',
              '-Wl,--gc-sections',
            ],
            if (isAppleTarget) ...[
              '-headerpad_max_install_names',
              // clang would use the temporary directory passed by
              // native_toolchain_c otherwise. So this makes improves
              // reproducibility.
              '-install_name',
              '@rpath/libsqlite3.dylib',
              if (isSqlcipher) ...[
                // We want to link Security.framework for CommonCrypt. Adding
                // this to CLibrary.frameworks doesn't work because that option
                // is only considered for Objective-C inputs.
                '-framework', 'Foundation',
                '-framework', 'Security',
              ],
            ],
          ],
          libraryDirectories: [
            if (openSslStaticLib != null && targetOS != OS.windows)
              openSslStaticLib.parent.path,
          ],
          libraries: [
            if (targetOS == OS.android) ...[
              // We need to link the math library on Android.
              'm',
              if (isSqlcipher) 'log',
            ],
            // Link with OpenSSL (SQLCipher builds)
            if (openSslCompileDir != null && targetOS != OS.windows) 'crypto',
            if (openSslStaticLib != null && targetOS == OS.windows) ...[
              p.withoutExtension(openSslStaticLib.path),
              'crypt32',
              'user32',
              'advapi32',
              'Ws2_32',
            ],
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

String _getOpenSslLibFolderName(OS os, Architecture architecture) {
  return switch ((os, architecture)) {
    (OS.linux, Architecture.x64) => 'lib64',
    _ => 'lib',
  };
}

const package = 'sqlite3';
const name = 'src/ffi/libsqlite3.g.dart';
