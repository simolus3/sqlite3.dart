import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Runs `all_native_tests.dart` as a single AOT-compiled executable.
///
/// Usage: `dart run run.dart`.
void main(List<String> args) async {
  const nativeAssetsSpec = '.dart_tool/native_assets.yaml';
  if (!await File(nativeAssetsSpec).exists()) {
    throw 'Expected $nativeAssetsSpec to exist, are you using dart run?';
  }

  final parser = ArgParser(allowTrailingOptions: false);
  parser.addOption('sanitizer', allowed: ['asan', 'msan', 'tsan']);
  final result = parser.parse(args);
  final sanitizer = result.option('sanitizer');

  final dir = await Directory.systemTemp.createTemp('pkg-sqlite3-test');
  final aotPath = p.join(dir.path, 'test.aot');

  try {
    print('AOT-compiling tests');
    final result = await Process.run(Platform.executable, [
      'compile',
      'aot-snapshot',
      'all_native_tests.dart',
      '--output',
      aotPath,
      if (sanitizer != null) '--target-sanitizer=$sanitizer',
      '--extra-gen-kernel-options=--native-assets=$nativeAssetsSpec',
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
    await process.exitCode;
  } finally {
    await dir.delete(recursive: true);
  }
}
