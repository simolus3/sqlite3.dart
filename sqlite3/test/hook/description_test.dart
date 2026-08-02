@TestOn('vm')
library;

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/src/hook/asset_hashes.dart';
import 'package:sqlite3/src/hook/compile/description.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../../hook/build.dart' as hook;

void main() {
  test('system with custom name', () async {
    await testBuildHook(
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {'source': 'system', 'name': 'sqlcipher'},
          basePath: Uri.file(d.sandbox),
        ),
      ),
      mainMethod: hook.main,
      check: (input, output) {
        expect(output.assets.code, [
          isA<CodeAsset>().having(
            (e) => e.linkMode,
            'linkMode',
            DynamicLoadingSystem(Uri.parse('sqlcipher.dll')),
          ),
        ]);
      },
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.arm64,
          targetOS: OS.windows,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
    );
  });

  test('resolves relative paths against the pubspec', () async {
    await testBuildHook(
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'source': 'source',
            'path': 'native/sqlite3.c',
            'additional_includes': ['native/include', '/absolute/include'],
            'additional_lib_directories': ['native/lib'],
          },
          basePath: Uri.file(p.join(d.sandbox, 'pubspec.yaml')),
        ),
      ),
      mainMethod: (args) {
        return build(args, (input, outputs) async {
          final config = SqliteBinary.forBuild(input) as CompileSqlite;

          expect(config.sourceFile, p.join(d.sandbox, 'native', 'sqlite3.c'));
          expect(config.additionalIncludes, [
            p.join(d.sandbox, 'native', 'include'),
            '/absolute/include',
          ]);
          expect(config.additionalLibraryDirectories, [
            p.join(d.sandbox, 'native', 'lib'),
          ]);
        });
      },
      check: (_, _) {},
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.arm64,
          targetOS: OS.macOS,
          linkModePreference: LinkModePreference.dynamic,
          macOS: MacOSCodeConfig(targetVersion: 13),
        ),
      ],
    );
  });

  test('can use custom download url', () async {
    await testBuildHook(
      mainMethod: (args) {
        return build(args, (input, outputs) async {
          final config =
              SqliteBinary.forBuild(input) as PrecompiledFromGithubAssets;

          expect(
            config.downloadUri('test.so').toString(),
            'https://github.com/simolus3/sqlite3.dart/releases/download/$releaseTag/test.so',
          );
        });
      },
      check: (_, _) {},
      extensions: [],
    );

    await testBuildHook(
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'source': 'sqlcipher',
            'url_pattern':
                r'https://artifacts.example.org/$RELEASE_TAG/$FILENAME',
          },
          basePath: Uri.file(d.sandbox),
        ),
      ),
      mainMethod: (args) {
        return build(args, (input, outputs) async {
          final config =
              SqliteBinary.forBuild(input) as PrecompiledFromGithubAssets;

          expect(
            config.downloadUri('test.so').toString(),
            'https://artifacts.example.org/$releaseTag/test.so',
          );
        });
      },
      check: (_, _) {},
      extensions: [],
    );
  });
}
