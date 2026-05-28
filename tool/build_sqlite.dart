import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:pool/pool.dart';
import 'package:path/path.dart' as p;

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

  for (final mode in SqliteFork.values) {
    final sourcePath = fs.currentDirectory.parent
        .childDirectory('sqlite-src')
        .childDirectory(mode.directoryName)
        .childFile(mode.amalgamationFileName)
        .path;

    Future<void> buildAndCopy(OS os, Architecture architecture,
        {IOSCodeConfig? iOS, String? osNameOverride}) async {
      final osName = osNameOverride ?? os.name;
      CCompilerConfig? compilerConfig;

      if (os == OS.iOS || os == OS.macOS) {
        // Ensure we use an XCode toolchain to avoid issues when uploading apps
        // to AppStore connect.
        final xcode = Process.runSync('xcode-select', ['-p']);
        final [path] = const LineSplitter().convert(xcode.stdout);

        Uri tool(String name) {
          return Uri.file(p.join(
              path, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/$name'));
        }

        compilerConfig = CCompilerConfig(
          archiver: tool('ar'),
          compiler: tool('clang'),
          linker: tool('ld'),
        );
      }

      await testBuildHook(
        extensions: [
          CodeAssetExtension(
            cCompiler: compilerConfig,
            targetArchitecture: architecture,
            targetOS: os,
            linkModePreference: LinkModePreference.dynamic,
            iOS: iOS,
            macOS: os == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
            android:
                os == OS.android ? AndroidCodeConfig(targetNdkApi: 24) : null,
          )
        ],
        linkingEnabled: true,
        mainMethod: hook.main,
        check: (_, output) async {
          final name = os.dylibFileName(
              '${mode.directoryName}.${architecture.name}.${osName}');
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
            'path': p.relative(sourcePath, from: fs.currentDirectory.path),
            if (mode == SqliteFork.sqlcipher) ...{
              'defines': {
                'default_options': true,
                'defines': [
                  'SQLITE_HAS_CODEC=1',
                  'SQLITE_EXTRA_INIT=sqlcipher_extra_init',
                  'SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown',
                  // SQLCipher uses it in their Community builds.
                  // Not clear if it has an impact in all applications
                  // https://github.com/sqlcipher/sqlcipher-android/blob/7fab57af75039e5004b087086142b11a9d2a2380/sqlcipher/src/main/jni/sqlcipher/Android.mk#L9
                  'SQLITE_ENABLE_MEMORY_MANAGEMENT=1',
                  if (os case OS.iOS || OS.macOS)
                    // Link with CommonCrypto on Apple platforms
                    'SQLCIPHER_CRYPTO_CC=1',
                ]
              },
              'is_sqlcipher': true,
            }
          },
          basePath: fs.currentDirectory.uri,
        )),
      );
    }

    void scheduleTask(Future<void> Function() task) {
      buildTasks.add(_limitConcurrency.withResource(task));
    }

    for (final os in operatingSystems) {
      if (mode == SqliteFork.sqlcipher &&
          (os == OS.android || os == OS.windows)) {
        // TODO: Port SQLCipher builds to other operating systems.
        continue;
      }

      for (final architecture in _osToAbis[os]!) {
        // Compiling sqlite3mc for x86 on Linux does not work.
        if (mode == SqliteFork.sqlite3mc &&
            os == OS.linux &&
            architecture == Architecture.ia32) {
          continue;
        }

        scheduleTask(() => buildAndCopy(os, architecture,
            iOS: IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 12)));
      }

      if (os == OS.iOS) {
        // Also compile for iOS simulators
        final simulatorConfig =
            IOSCodeConfig(targetSdk: IOSSdk.iPhoneSimulator, targetVersion: 12);

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

enum SqliteFork {
  sqlite('sqlite3', 'sqlite3.c'),
  sqlite3mc('sqlite3mc', 'sqlite3mc_amalgamation.c'),
  sqlcipher('sqlcipher', 'sqlcipher_amalgamation.c');

  final String directoryName;
  final String amalgamationFileName;

  const SqliteFork(this.directoryName, this.amalgamationFileName);
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
