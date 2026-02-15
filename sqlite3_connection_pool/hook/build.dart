import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) {
  return build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final sourceRoot = input.packageRoot;
    final config = input.config.code;
    final outputName = config.targetOS.dylibFileName('sqlite3_connection_pool');

    // For versions of this package that are published to pub.dev, assets for
    // all supported ABIs are copied to lib/src/precompiled. Use those if
    // available.
    final precompiled = sourceRoot.resolve('lib/src/precompiled/');
    if (Directory.fromUri(precompiled).existsSync()) {
      final outputPath = input.outputDirectory.resolve(outputName);

      String assetName;
      if (config.targetOS == OS.iOS &&
          config.iOS.targetSdk == IOSSdk.iPhoneOS) {
        assetName = 'libsqlite3_connection_pool.ios_aarch64.dylib';
      } else if (_prebuiltAssets[(config.targetOS, config.targetArchitecture)]
          case final asset?) {
        assetName = config.targetOS.dylibFileName(
          'sqlite3_connection_pool.$asset',
        );
      } else {
        throw ArgumentError(
          'Unsupported target ABI: ${config.targetArchitecture} on '
          '${config.targetOS}. Please file an issue on '
          'https://github.com/simolus3/sqlite3.dart/ !',
        );
      }

      File.fromUri(
        precompiled.resolve(assetName),
      ).copySync(outputPath.toFilePath());

      output.assets.code.add(
        CodeAsset(
          package: 'sqlite3_connection_pool',
          name: 'sqlite3_connection_pool.dart',
          linkMode: DynamicLoadingBundled(),
          file: outputPath,
        ),
      );
    } else {
      // We can't use precompiled assets, use cargo to compile for the current
      // platform.
      if (config.targetOS != OS.current ||
          config.targetArchitecture != Architecture.current) {
        throw UnsupportedError(
          'Since lib/src/precompiled is missing, this hook only supports '
          'the host ABI.',
        );
      }

      final build = await Process.start('cargo', [
        'build',
      ], mode: ProcessStartMode.inheritStdio);
      if (await build.exitCode case final code when code != 0) {
        throw StateError('Rust build failed: exit code $code');
      }

      output.assets.code.add(
        CodeAsset(
          package: 'sqlite3_connection_pool',
          name: 'sqlite3_connection_pool.dart',
          linkMode: DynamicLoadingBundled(),
          file: sourceRoot.resolve('target/debug/$outputName'),
        ),
      );
    }
  });
}

const _prebuiltAssets = {
  (OS.windows, Architecture.x64): 'win_x64',
  (OS.windows, Architecture.arm64): 'win_aarch64',

  (OS.macOS, Architecture.x64): 'macos_x64',
  (OS.macOS, Architecture.arm64): 'macos_aarch64',

  // Note: The non-simulator build is special-cased as a lookup.
  (OS.iOS, Architecture.x64): 'ios_sim_x64',
  (OS.iOS, Architecture.arm64): 'ios_sim_aarch64',

  (OS.linux, Architecture.x64): 'linux_x64',
  (OS.linux, Architecture.riscv64): 'linux_riscv',
  (OS.linux, Architecture.arm): 'linux_arm7',
  (OS.linux, Architecture.arm64): 'linux_aarch64',

  (OS.android, Architecture.arm64): 'android_v8a',
  (OS.android, Architecture.x64): 'android_x86_64',
  (OS.android, Architecture.arm): 'android_v7a',
};
