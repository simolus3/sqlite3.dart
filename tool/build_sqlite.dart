import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:pool/pool.dart';

import '../sqlite3/hook/build.dart' as hook;

final _limitConcurrency = Pool(Platform.numberOfProcessors);

/// Invokes `package:sqlite3` build hooks for multiple operating systems and
/// architectures, merging outputs into `sqlite3-compiled/`.
void main(List<String> args) async {
  Directory.current = Directory('sqlite3');

  var operatingSystems = args.map(OS.fromString).toList();
  if (operatingSystems.isEmpty) {
    if (Platform.isLinux) {
      operatingSystems = [OS.linux, OS.android];
    } else if (Platform.isMacOS) {
      operatingSystems = [OS.macOS, OS.iOS];
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

  final outputDirectory =
      fs.currentDirectory.parent.childDirectory('sqlite-compiled');
  print('Compiling to ${outputDirectory.path}');

  if (await outputDirectory.exists()) {
    await outputDirectory.delete(recursive: true);
  }
  await outputDirectory.create();

  final buildTasks = <Future<void>>[];

  for (final mode in ['sqlite3', 'sqlite3mc']) {
    final sourcePath = fs.currentDirectory.parent
        .childDirectory('sqlite-src')
        .childDirectory(mode)
        .childFile(mode == 'sqlite3' ? 'sqlite3.c' : 'sqlite3mc_amalgamation.c')
        .path;

    Future<void> buildAndCopy(OS os, Architecture architecture,
        {IOSCodeConfig? iOS, String? osNameOverride}) async {
      final osName = osNameOverride ?? os.name;

      await testBuildHook(
        extensions: [
          CodeAssetExtension(
            targetArchitecture: architecture,
            targetOS: os,
            linkModePreference: LinkModePreference.dynamic,
            iOS: iOS,
            macOS: os == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
            android:
                os == OS.android ? AndroidCodeConfig(targetNdkApi: 24) : null,
          )
        ],
        mainMethod: hook.main,
        check: (_, output) async {
          final name =
              os.dylibFileName('${mode}.${architecture.name}.${osName}');
          for (final file in output.assets.code) {
            await fs
                .file(file.file!)
                .copy(outputDirectory.childFile(name).path);
          }
        },
        userDefines: PackageUserDefines(
            workspacePubspec: PackageUserDefinesSource(
          defines: {
            'source': 'source',
            'path': sourcePath,
          },
          basePath: fs.currentDirectory.uri,
        )),
      );
    }

    void scheduleTask(Future<void> Function() task) {
      buildTasks.add(_limitConcurrency.withResource(task));
    }

    for (final os in operatingSystems) {
      for (final architecture in _osToAbis[os]!) {
        // Compiling sqlite3mc for x86 on Linxu does not work.
        if (mode == 'sqlite3mc' &&
            os == OS.linux &&
            architecture == Architecture.ia32) {
          continue;
        }

        scheduleTask(() => buildAndCopy(os, architecture,
            iOS: IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 13)));
      }

      if (os == OS.iOS) {
        // Also compile for iOS simulators
        final simulatorConfig =
            IOSCodeConfig(targetSdk: IOSSdk.iPhoneSimulator, targetVersion: 13);

        scheduleTask(() => buildAndCopy(os, Architecture.arm64,
            iOS: simulatorConfig, osNameOverride: 'ios_sim'));
        scheduleTask(() => buildAndCopy(os, Architecture.x64,
            iOS: simulatorConfig, osNameOverride: 'ios_sim'));
      }
    }
  }

  await Future.wait(buildTasks, eagerError: true);
  print('Done building');
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
