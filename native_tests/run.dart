import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Runs `all_native_tests.dart` as a single AOT-compiled executable.
///
/// Usage: `dart run run.dart`.
void main(List<String> args) async {
  final parser = ArgParser(allowTrailingOptions: false);
  parser.addOption('sanitizer', allowed: ['asan', 'msan', 'tsan']);
  final result = parser.parse(args);
  final sanitizer = result.option('sanitizer');

  final dir = await Directory.systemTemp.createTemp('pkg-sqlite3-test');
  final aotPath = p.join(dir.path, 'test.aot');
  final assetsConfig = await _createNativeAssetsConfig(dir, sanitizer);

  try {
    print('AOT-compiling tests');
    final result = await Process.run(Platform.executable, [
      'compile',
      'aot-snapshot',
      'all_native_tests.dart',
      '--output',
      aotPath,
      if (sanitizer != null) '--target-sanitizer=$sanitizer',
      '--extra-gen-kernel-options=--native-assets=${assetsConfig.path}',
    ]);

    if (result.exitCode != 0 || !await File(aotPath).exists()) {
      throw '''
could not compile test script

exitCode: ${result.exitCode}
stdout: ${result.stdout}
stderr: ${result.stderr}
''';
    }

    var runtimeName = 'dartaotruntime';
    if (sanitizer != null) runtimeName += '_$sanitizer';
    if (Platform.isWindows) runtimeName += '.exe';

    print('Running with $runtimeName');
    final runtime = p.join(p.dirname(Platform.resolvedExecutable), runtimeName);
    final process = await Process.start(runtime, [
      aotPath,
    ], mode: ProcessStartMode.inheritStdio);
    final exit = await process.exitCode;
    if (exit != 0) {
      throw 'Expected exit code 0, got $exit';
    }
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<File> _createNativeAssetsConfig(
  Directory tmpForRun,
  String? sanitizer,
) async {
  if (sanitizer == null) {
    final file = File('.dart_tool/native_assets.yaml');
    if (!await file.exists()) {
      throw 'Expected $file to exist, are you using dart run?';
    }

    return file;
  }

  final name = switch (sanitizer) {
    'asan' => 'address',
    'msan' => 'memory',
    'tsan' => 'thread',
    _ => throw AssertionError(),
  };
  final sqliteFile = p.normalize(
    p.absolute('../sqlite-sanitized', 'sqlite3.san_$name.so'),
  );
  final poolFile = p.normalize(
    p.absolute(
      '../sqlite-sanitized',
      'libsqlite3_connection_pool.$name.san.so',
    ),
  );

  final yaml =
      '''
format-version: [1, 0, 0]
native-assets:
  linux_x64:
    "package:sqlite3/src/ffi/libsqlite3.g.dart":
      - absolute
      - "$sqliteFile"
    "package:sqlite3_connection_pool/sqlite3_connection_pool.dart":
      - absolute
      - "$poolFile"
''';

  final file = File(p.join(tmpForRun.path, 'assets.yaml'));
  await file.writeAsString(yaml);
  return file;
}
