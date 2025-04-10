@TestOn('linux') // Need to update assertions for other platforms
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:yaml/yaml.dart';

void main() {
  test('can use sqlite from system', () async {
    await _setupTest('''
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        system:
''');

    await _compileNativeAssets();
    await _expectNativeAsset({
      _key: ['system', 'libsqlite3.so'],
    });
  });

  test('can use sqlite from process', () async {
    await _setupTest('''
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        process:
''');

    await _compileNativeAssets();
    await _expectNativeAsset({
      _key: ['process'],
    });
  });

  test('can use sqlite from executable', () async {
    await _setupTest('''
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        executable:
''');

    await _compileNativeAssets();
    await _expectNativeAsset({
      _key: ['executable'],
    });
  });

  test('can use custom source', () async {
    await _setupTest(
      '''
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        local: my_sqlite.c
      defines:
        defines:
          FOO: "1"
''',
      additionalSources: [
        d.file('my_sqlite.c', '''
#ifdef FOO
void foo() {}
#endif

void bar() {}
'''),
      ],
    );

    await _compileNativeAssets();
    await _expectNativeAsset({
      _key: [
        'absolute',
        endsWith('.dart_tool/native_assets/lib/libsqlite3.so'),
      ],
    });

    final config = loadYaml(
      await File(d.path('app/.dart_tool/native_assets.yaml')).readAsString(),
    );
    final sharedLibrary = File(config['native-assets'].values.single[_key][1]);
    final symbols = await Process.run('nm', ['-D', sharedLibrary.path]);
    expect(symbols.stdout, allOf(contains('foo'), contains('bar')));
  });
}

Future<void> _setupTest(
  String options, {
  List<d.Descriptor> additionalSources = const [],
}) async {
  // Instead of running `pub get` for each test, we just copy the package
  // config used by this test and add sqlite3_native_assets.
  final uri = await Isolate.packageConfig;
  final config = PackageConfig.parseBytes(
    await File.fromUri(uri!).readAsBytes(),
    uri,
  );
  final appRoot = join(d.sandbox, 'app');
  final nativeAssetsRoot = absolute('../../sqlite3_native_assets');

  final appUri = '${File(appRoot).absolute.uri}/';
  final nativeAssetsUri = '${File(nativeAssetsRoot).absolute.uri}/';
  final newConfig = PackageConfig([
    ...config.packages,
    Package(
      'app',
      Uri.parse(appUri),
      packageUriRoot: Uri.parse('${appUri}lib/'),
    ),
    Package(
      'sqlite3_native_assets',
      Uri.parse(nativeAssetsUri),
      packageUriRoot: Uri.parse('${nativeAssetsUri}lib/'),
    ),
  ]);
  final configBuffer = StringBuffer();
  PackageConfig.writeString(newConfig, configBuffer);

  await d.dir('app', [
    d.dir('.dart_tool', [
      d.file('package_config.json', configBuffer.toString()),
      d.file('package_graph.json', json.encode(_fakePackageGraph)),
    ]),
    d.file('pubspec.yaml', '''
name: app

environment:
  sdk: ^3.7.0

dependencies:
  sqlite3: ^10.10.10 # should not resolve
  sqlite3_native_assets:

$options
'''),
    d.file('app.dart', '''
void main() {}
'''),
    ...additionalSources,
  ]).create();
}

Future<void> _compileNativeAssets() async {
  final dart = Platform.executable;

  // Just run some bogus command guaranteed to trigger native assets.
  final process = await Process.start(dart, [
    '--enable-experiment=native-assets',
    'run',
    'app.dart',
  ], workingDirectory: join(d.sandbox, 'app'));
  final stderr = process.stderr.transform(const Utf8Decoder()).join();

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    fail('Compiling dart failed (at ${d.sandbox}), $exitCode, ${await stderr}');
  }
}

const _fakePackageGraph = {
  "root": "app",
  "packages": [
    {
      "name": "app",
      "version": "0.0.0",
      "kind": "root",
      "source": "root",
      "dependencies": ["sqlite3", "sqlite3_native_assets"],
      "directDependencies": ["sqlite3", "sqlite3_native_assets"],
      "devDependencies": [],
    },
    {
      "name": "sqlite3_native_assets",
      "version": "0.0.3",
      "kind": "direct",
      "source": "hosted",
      "dependencies": ["sqlite3", "native_assets_cli", "native_toolchain_c"],
      "directDependencies": [
        "sqlite3",
        "native_assets_cli",
        "native_toolchain_c",
      ],
    },
    {
      "name": "native_toolchain_c",
      "version": "0.8.0",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": ["native_assets_cli"],
      "directDependencies": ["native_assets_cli"],
    },
    {
      "name": "native_assets_cli",
      "version": "0.11.0",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [],
      "directDependencies": [],
    },
    {
      "name": "sqlite3",
      "version": "2.7.5",
      "kind": "direct",
      "source": "hosted",
      "dependencies": [],
      "directDependencies": [],
    },
  ],
  "sdks": [
    {"name": "Dart", "version": "3.7.2"},
  ],
  "executables": [],
};

Future<void> _expectNativeAsset(Object? expected) async {
  final config = loadYaml(
    await File(d.path('app/.dart_tool/native_assets.yaml')).readAsString(),
  );

  /*
# Native assets mapping for host OS in JIT mode.
# Generated by dartdev and package:native_assets_builder.

format-version:
  - 1
  - 0
  - 0
native-assets:
  linux_x64:
    package:sqlite3_native_assets/sqlite3_native_assets.dart:
      - system
      - libsqlite3.so
  */

  final map = config['native-assets'].values.single;
  expect(map, expected);
}

const _key = 'package:sqlite3_native_assets/sqlite3_native_assets.dart';
