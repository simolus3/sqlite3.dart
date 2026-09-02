import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:uuid/uuid.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart' show sha256;

import 'download_sqlite.dart' as download_sqlite;

const openSslVersion = '3.6.4';

/// Generates a CycloneDX SBOM for precompiled artifacts we attach to GitHub
/// releases.
///
/// These SBOMs don't contain Dart dependencies (as those are trivial for users
/// to infer through the pub dependency graph), only binaries.
void main(List<String> args) async {
  final (sqliteDirectory, poolDirectory) = switch (args) {
    [final sqlite, final pool] => (Directory(sqlite), Directory(pool)),
    _ => throw ArgumentError(
        'Usage: dart tool/generate_sbom.dart <path to pool libraries> '
        '<path to sqlite libraries>')
  };

  final output = Directory('sbom');
  if (await output.exists()) {
    await output.delete(recursive: true);
  }

  await output.create();
  final encoder = JsonEncoder.withIndent(' ' * 2).fuse(Utf8Encoder());

  final writes = <Future<void>>[];
  void generateAndWriteSbom(String path,
      Future<Object?> Function(Directory) function, Directory input) {
    writes.add(Future(() async {
      final sbom = await _generateOnIsolate(function, input);
      await File('sbom/$path').writeAsBytes(encoder.convert(sbom));
    }));
  }

  generateAndWriteSbom(
      'sqlite3.bom.json', _generateForSqlite3, sqliteDirectory);
  generateAndWriteSbom(
      'sqlite3mc.bom.json', _generateForSqliteMultipleCiphers, sqliteDirectory);
  generateAndWriteSbom(
      'sqlcipher.bom.json', _generateForSqlCipher, sqliteDirectory);
  generateAndWriteSbom('connection_pool.bom.json',
      _generateForSqlite3ConnectionPool, poolDirectory);
  await writes.wait;
}

Future<Object?> _generateOnIsolate(
    Future<Object?> Function(Directory) generate, Directory directory) async {
  return await Isolate.run(() => generate(directory));
}

typedef _Binary = ({String ref, String name, Map<String, Object?> component});

Future<List<_Binary>> _scanBinaries(Directory directory,
    [bool Function(String name)? matches]) async {
  final binaries = <_Binary>[];
  await for (final entry in directory.list()) {
    final name = p.basename(entry.path);
    if (matches != null && !matches(name)) continue;

    final ref = 'binary-${binaries.length}';
    binaries.add((
      ref: ref,
      name: name,
      component: {
        'name': name,
        'bom-ref': ref,
        'type': 'library',
        'hashes': [
          {'alg': 'SHA-256', 'content': await _sha256(entry as File)}
        ],
      },
    ));
  }
  return binaries;
}

/// Builds the `metadata` block describing the pub package that the SBOM is
/// generated for.
Map<String, Object?> _metadata({
  required String name,
  required String version,
  required String docsPath,
  String? bomRef,
}) {
  return {
    'timestamp': DateTime.now().toIso8601String(),
    'lifecycles': [
      {'phase': 'post-build'}
    ],
    'authors': _authors,
    'component': {
      'type': 'library',
      'authors': _authors,
      'name': name,
      'version': version,
      'licenses': [
        {'expression': 'MIT'}
      ],
      if (bomRef != null) 'bom-ref': bomRef,
      'externalReferences': [
        {'type': 'vcs', 'url': 'https://github.com/simolus3/sqlite3.git'},
        {
          'type': 'documentation',
          'url': 'https://pub.dev/documentation/$docsPath/'
        },
      ],
    },
  };
}

Map<String, Object?> _bom({
  required Map<String, Object?> metadata,
  required List<Object?> components,
  required List<Object?> dependencies,
}) {
  return {
    ..._commonFields(),
    'metadata': metadata,
    'components': components,
    'dependencies': dependencies,
  };
}

Future<Object?> _generateForSqlite3(Directory precompiledLibraries) async {
  final pubspec = await _parsePubspec('sqlite3');
  var versionNumber =
      int.parse(download_sqlite.sqlitePath.split('-')[2]) ~/ 100;
  final sqlite3Patch = versionNumber % 100;
  versionNumber ~/= 100;
  final sqlite3Minor = versionNumber % 100;
  versionNumber ~/= 100;
  final sqlite3Major = versionNumber;
  final version = '$sqlite3Major.$sqlite3Minor.$sqlite3Patch';

  final binaries = await _scanBinaries(precompiledLibraries,
      (name) => name.startsWith('libsqlite3.') || name.startsWith('sqlite3.'));

  return _bom(
    metadata: _metadata(
      name: 'sqlite3',
      version: pubspec.version.toString(),
      docsPath: 'sqlite3',
      bomRef: 'pkg-sqlite3',
    ),
    components: [
      {
        'version': version,
        'bom-ref': 'sqlite3',
        'license': [
          {'expression': 'blessing'}
        ],
        'externalReferences': [
          {'url': 'https://sqlite.org/', 'type': 'website'},
        ],
        'cpe': 'cpe:2.3:a:sqlite:sqlite:$version:*:*:*:*:*:*:*',
      },
      for (final binary in binaries) binary.component,
    ],
    dependencies: [
      for (final binary in binaries)
        {
          'ref': binary.ref,
          'dependsOn': ['sqlite3'],
        }
    ],
  );
}

Future<Object?> _generateForSqliteMultipleCiphers(
    Directory precompiledLibraries) async {
  final pubspec = await _parsePubspec('sqlite3');
  final ciphersUri = Uri.parse(download_sqlite.sqliteMultipleCiphersSource);
  // Format: utelle/SQLite3MultipleCiphers/releases/download/v$version
  final ciphersVersion = ciphersUri.pathSegments[4].substring(1);

  final binaries = await _scanBinaries(
      precompiledLibraries,
      (name) =>
          name.startsWith('libsqlite3mc.') || name.startsWith('sqlite3mc.'));

  return _bom(
    metadata: _metadata(
      name: 'sqlite3',
      version: pubspec.version.toString(),
      docsPath: 'sqlite3',
      bomRef: 'pkg-sqlite3',
    ),
    components: [
      {
        'version': ciphersVersion,
        'bom-ref': 'sqlite3mc',
        'license': [
          {'expression': 'MIT'}
        ],
        'externalReferences': [
          {
            'type': 'vcs',
            'url': 'https://github.com/utelle/SQLite3MultipleCiphers'
          },
          {
            'url': 'https://utelle.github.io/SQLite3MultipleCiphers/',
            'type': 'website'
          },
        ],
      },
      for (final binary in binaries) binary.component,
    ],
    dependencies: [
      for (final binary in binaries)
        {
          'ref': binary.ref,
          'dependsOn': ['sqlite3mc'],
        }
    ],
  );
}

Future<Object?> _generateForSqlCipher(Directory precompiledLibraries) async {
  final pubspec = await _parsePubspec('sqlite3');

  final binaries = await _scanBinaries(
      precompiledLibraries,
      (name) =>
          name.startsWith('libsqlcipher.') || name.startsWith('sqlcipher.'));

  return _bom(
    metadata: _metadata(
      name: 'sqlite3',
      version: pubspec.version.toString(),
      docsPath: 'sqlite3',
      bomRef: 'pkg-sqlite3',
    ),
    components: [
      {
        'version': download_sqlite.sqlcipherVersion,
        'bom-ref': 'sqlcipher',
        'license': [
          {'expression': 'BSD-3-Clause'}
        ],
        'externalReferences': [
          {'type': 'vcs', 'url': 'https://github.com/sqlcipher/sqlcipher'},
          {'url': 'https://www.zetetic.net/sqlcipher/', 'type': 'website'},
        ],
        'cpe':
            'cpe:2.3:a:zetetic:sqlcipher:${download_sqlite.sqlcipherVersion}:*:*:*:*:*:*:*',
      },
      {
        'version': openSslVersion,
        'bom-ref': 'openssl',
        'license': [
          {'expression': 'Apache-2.0'}
        ],
        'externalReferences': [
          {'type': 'vcs', 'url': 'https://github.com/openssl/openssl/'},
          {'url': 'https://openssl-library.org/', 'type': 'website'},
        ],
        'cpe': 'cpe:2.3:a:openssl:openssl:$openSslVersion:*:*:*:*:*:*:*',
      },
      for (final binary in binaries) binary.component,
    ],
    dependencies: [
      for (final binary in binaries)
        {
          'ref': binary.ref,
          'dependsOn': [
            'sqlcipher',
            // Outside of Apple platforms, we statically link OpenSSL into
            // our SQLCipher build.
            if (binary.name.contains('windows') ||
                binary.name.contains('linux') ||
                binary.name.contains('android'))
              'openssl',
          ],
        }
    ],
  );
}

Future<Object?> _generateForSqlite3ConnectionPool(
    Directory poolLibraries) async {
  // Currently, all Rust dependencies end up in the library (we have no build or
  // proc-macro dependencies).
  final processOutput = await Process.run(
    'cargo',
    ['metadata', '--format-version=1'],
    workingDirectory: 'sqlite3_connection_pool',
  );
  if (processOutput.exitCode != 0) {
    throw 'Could not run cargo metadata: ${processOutput.stderr}';
  }

  final cargoMetadata = jsonDecode(processOutput.stdout);
  final packages =
      (cargoMetadata['packages'] as List).cast<Map<String, Object?>>();
  final pubspec = await _parsePubspec('sqlite3_connection_pool');

  final binaries = await _scanBinaries(poolLibraries);

  final cargoComponents = <Object?>[];
  final cargoRefs = <String>[];
  for (final package in packages) {
    final name = package['name'] as String;
    if (name == 'sqlite3_connection_pool') {
      // We'll generate the component for this manually.
      continue;
    }

    final version = package['version'] as String;
    final license = package['license'] as String;
    final description = package['description'] as String;
    final bomRef = 'cargo@$name@$version';
    cargoRefs.add(bomRef);

    cargoComponents.add({
      'name': name,
      'purl': 'pkg:cargo/$name@$version',
      'type': 'library',
      'version': version,
      'licenses': [
        {'expression': license}
      ],
      'bom-ref': bomRef,
      'description': description,
      'externalReferences': [
        if (package['repository'] case final String repository)
          {'type': 'vcs', 'url': repository},
        if (package['homepage'] case final String homepage)
          {'type': 'website', 'url': homepage},
        if (package['documentation'] case final String documentation)
          {'type': 'documentation', 'url': documentation},
      ],
      if (package['authors'] case [final String author]) 'author': author,
    });
  }

  return _bom(
    metadata: _metadata(
      name: 'sqlite3_connection_pool',
      version: pubspec.version.toString(),
      docsPath: 'sqlite3_connection_pool',
    ),
    components: [
      for (final binary in binaries) binary.component,
      ...cargoComponents,
    ],
    dependencies: [
      for (final binary in binaries)
        {
          'ref': binary.ref,
          'dependsOn': cargoRefs,
        }
    ],
  );
}

Future<Pubspec> _parsePubspec(String package) async {
  final file = File('$package/pubspec.yaml');
  return Pubspec.parse(await file.readAsString(), sourceUrl: file.uri);
}

const _authors = [
  {'name': 'Simon Binder', 'email': 'oss@simonbinder.eu'}
];

Map<String, Object?> _commonFields() {
  return {
    'bomFormat': 'CycloneDX',
    'specVersion': '1.7',
    'serialNumber': 'urn:uuid:${const Uuid().v4()}',
    'version': 1,
  };
}

Future<String> _sha256(File file) async {
  final digest = sha256.convert(await file.readAsBytes());
  return digest.toString();
}
