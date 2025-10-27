import 'dart:io';
import 'dart:isolate';

import 'package:code_assets/code_assets.dart';
import 'package:file/local.dart';
import 'package:hooks_runner/hooks_runner.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:pool/pool.dart';

final _compileTasks = Pool(Platform.numberOfProcessors);

/// Invokes `package:sqlite3` build hooks for multiple operating systems and
/// architectures, merging outputs into `sqlite3-compiled/`.
void main(List<String> args) async {
  hierarchicalLoggingEnabled = true;
  Logger('sqlite3').onRecord.listen((record) {
    print('[${record.loggerName}]: ${record.message}');
  });

  var operatingSystems = args.map(OS.fromString).toList();
  if (operatingSystems.isEmpty) {
    if (Platform.isLinux) {
      operatingSystems = [OS.linux, OS.android];
    } else if (Platform.isMacOS) {
      operatingSystems = [OS.macOS];
    } else if (Platform.isWindows) {
      operatingSystems = [OS.windows];
    }
  }

  if (operatingSystems.isEmpty) {
    print('Usage: dart run tool/build_sqlite3.dart <operating systems...>');
    exit(1);
  }
  print('Compiling for $operatingSystems');

  const fs = LocalFileSystem();

  final outputDirectory = fs.directory('sqlite-compiled');
  print('Compiling to ${outputDirectory.path}');

  if (await outputDirectory.exists()) {
    await outputDirectory.delete(recursive: true);
  }
  await fs.directory('sqlite-compiled').create();

  final config = await Isolate.packageConfig;
  final packageLayout = PackageLayout.fromPackageConfig(
    fs,
    await loadPackageConfigUri(config!),
    config,
    'sqlite3',
    includeDevDependencies: false,
  );
  final definesDir = await fs.systemTempDirectory.createTemp('sqlite3-build');
  final compilationTasks = <Future<void>>[];

  for (final mode in ['sqlite3', 'sqlite3mc']) {
    final sourcePath = fs.currentDirectory
        .childDirectory('sqlite-src')
        .childDirectory(mode)
        .childFile(mode == 'sqlite3' ? 'sqlite3.c' : 'sqlite3mc_amalgamation.c')
        .absolute
        .path;

    final fakePubspec = definesDir.childFile('defines_$mode.pubspec.yaml');
    await fakePubspec.writeAsString('''
hooks:
  user_defines:
    sqlite3:
      source: source
      path: $sourcePath
''');

    Future<void> buildAndCopy(OS os, Architecture architecture,
        {IOSCodeConfig? iOS, String? osNameOverride}) async {
      final osName = osNameOverride ?? os.name;
      final runner = NativeAssetsBuildRunner(
        logger: Logger('sqlite3.$mode.${osName}.${architecture.name}'),
        dartExecutable: Uri.file(Platform.executable),
        fileSystem: fs,
        packageLayout: packageLayout,
        userDefines: UserDefines(workspacePubspec: fakePubspec.uri),
      );

      final name = os.dylibFileName('${mode}.${architecture.name}.${osName}');
      final result = await runner.build(
        extensions: [
          CodeAssetExtension(
            targetArchitecture: Architecture.x64,
            targetOS: OS.linux,
            linkModePreference: LinkModePreference.dynamic,
            iOS: iOS,
          )
        ],
        linkingEnabled: false,
      );

      if (result.isFailure) {
        throw result.asFailure.value;
      }

      final output = result.asSuccess.value;
      for (final file in output.encodedAssets) {
        if (file.isCodeAsset) {
          final code = file.asCodeAsset;
          await fs.file(code.file!).copy(outputDirectory.childFile(name).path);
        }
      }
    }

    for (final os in operatingSystems) {
      for (final architecture in _osToAbis[os]!) {
        compilationTasks.add(
            _compileTasks.withResource(() => buildAndCopy(os, architecture)));
      }

      if (os == OS.iOS) {
        // Also compile for iOS simulators
        final simulatorConfig =
            IOSCodeConfig(targetSdk: IOSSdk.iPhoneSimulator, targetVersion: 13);

        compilationTasks.add(_compileTasks.withResource(() => buildAndCopy(
            os, Architecture.arm64,
            iOS: simulatorConfig, osNameOverride: 'ios_sim')));
        compilationTasks.add(_compileTasks.withResource(() => buildAndCopy(
            os, Architecture.x64,
            iOS: simulatorConfig, osNameOverride: 'ios_sim')));
      }
    }
  }

  await Future.wait(compilationTasks, eagerError: true);
  print('Done building');
  await definesDir.delete(recursive: true);
}

const _osToAbis = {
  OS.linux: [
    Architecture.arm,
    Architecture.arm64,
    Architecture.ia32,
    Architecture.x64,
    Architecture.riscv64,
  ],
  OS.android: [
    Architecture.arm,
    Architecture.arm64,
    Architecture.ia32,
    Architecture.x64,
  ],
  OS.windows: [
    Architecture.arm64,
    Architecture.ia32,
    Architecture.x64,
  ],
  OS.macOS: [
    Architecture.arm64,
    Architecture.x64,
  ],
  OS.iOS: [
    Architecture.arm64,
    // Note: There's a special check to also compile simulator builds for x64
  ],
};
