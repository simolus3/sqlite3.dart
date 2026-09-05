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

  test('system with path-like name', () async {
    expect(
      await systemLinkMode(OS.iOS, {
        'source': 'system',
        'name_ios': 'my_lib.framework/my_lib',
      }),
      DynamicLoadingSystem(Uri.parse('my_lib.framework/my_lib')),
    );
    expect(
      await systemLinkMode(OS.macOS, {
        'source': 'system',
        'name': '@rpath/libsqlcipher.dylib',
      }),
      DynamicLoadingSystem(Uri.parse('@rpath/libsqlcipher.dylib')),
    );
    // Plain names are still turned into platform-specific file names.
    expect(
      await systemLinkMode(OS.iOS, {'source': 'system', 'name': 'sqlcipher'}),
      DynamicLoadingSystem(Uri.parse('libsqlcipher.dylib')),
    );
  });

  test('os-specific source', () async {
    const defines = {
      'source': {'ios': 'system', 'default': 'sqlite3'},
    };

    expect(
      await resolveForOS(OS.iOS, defines, (_, binary) => binary),
      isA<LookupSystem>(),
    );
    expect(
      await resolveForOS(OS.macOS, defines, (_, binary) => binary),
      isA<PrecompiledFromGithubAssets>(),
    );
  });

  test('os-specific name', () async {
    const defines = {
      'source': 'system',
      'name': {'ios': 'my_lib.framework/my_lib', 'default': 'sqlcipher'},
    };

    expect(
      await systemLinkMode(OS.iOS, defines),
      DynamicLoadingSystem(Uri.parse('my_lib.framework/my_lib')),
    );
    expect(
      await systemLinkMode(OS.macOS, defines),
      DynamicLoadingSystem(Uri.parse('libsqlcipher.dylib')),
    );
  });

  test('map without entry for target os', () async {
    expect(
      await resolveForOS(OS.macOS, {
        'source': {'android': 'system'},
      }, (_, binary) => binary),
      isA<PrecompiledFromGithubAssets>(),
    );
    expect(
      await systemLinkMode(OS.macOS, {
        'source': 'system',
        'name': {'android': 'my_lib'},
      }),
      DynamicLoadingSystem(Uri.parse('libsqlite3.dylib')),
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

          expect(config.sourceFiles, [
            p.join(d.sandbox, 'native', 'sqlite3.c'),
          ]);
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

  test('multiple source files', () async {
    await testBuildHook(
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'source': 'source',
            'path': ['native/sqlite3.c', 'native/extra.c'],
          },
          basePath: Uri.file(p.join(d.sandbox, 'pubspec.yaml')),
        ),
      ),
      mainMethod: (args) {
        return build(args, (input, outputs) async {
          final config = SqliteBinary.forBuild(input) as CompileSqlite;

          expect(config.sourceFiles, [
            p.join(d.sandbox, 'native', 'sqlite3.c'),
            p.join(d.sandbox, 'native', 'extra.c'),
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
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.arm64,
          targetOS: OS.linux,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
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
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.arm64,
          targetOS: OS.linux,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
    );
  });
}

/// Resolves the [SqliteBinary] for a build targeting [os] with [defines] as
/// user-defines and returns the result of [body].
Future<T> resolveForOS<T>(
  OS os,
  Map<String, Object?> defines,
  T Function(BuildInput input, SqliteBinary binary) body,
) async {
  late T result;
  await testBuildHook(
    userDefines: PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: defines,
        basePath: Uri.file(d.sandbox),
      ),
    ),
    mainMethod: (args) {
      return build(args, (input, output) async {
        result = body(input, SqliteBinary.forBuild(input));
      });
    },
    check: (_, _) {},
    extensions: [
      CodeAssetExtension(
        targetArchitecture: Architecture.arm64,
        targetOS: os,
        linkModePreference: LinkModePreference.dynamic,
        iOS: os == OS.iOS
            ? IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 13)
            : null,
        macOS: os == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
      ),
    ],
  );
  return result;
}

Future<LinkMode> systemLinkMode(OS os, Map<String, Object?> defines) {
  return resolveForOS(
    os,
    defines,
    (input, binary) => (binary as LookupSystem).resolveLinkMode(input),
  );
}
