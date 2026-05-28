import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// Compiles static OpenSSL libraries.
///
/// To use this script:
///
///   1. Download an OpenSSL 3.x release to `openssl-src/`.
///   2. `dart tool/build_openssl.dart <linux | android | windows>`.
void main(List<String> args) async {
  final src = Directory('openssl-src');
  if (!await src.exists()) {
    print('Expected openssl-src to exist');
    exit(1);
  }

  final target = Directory('openssl-compiled');
  if (await target.exists()) {
    await target.delete(recursive: true);
  }
  await target.create(recursive: true);

  var hadFailure = false;

  for (final platform in args) {
    switch (platform) {
      case 'linux':
        for (final arch in _linuxArchitectures) {
          try {
            await _buildOpenSSL(
              targetOS: OS.linux,
              targetArchitecture: arch,
              sharedOutputDirectory: target,
              openSslSrcDir: src,
            );
          } catch (e, s) {
            hadFailure = true;
            print('Build failed for $platform: $e');
            print(s);
          }
        }
      case 'windows':
        break;
      case 'android':
        break;
      default:
        throw UnsupportedError(
            'Unsupported target OS, expected linux, windows or android.');
    }
  }

  if (hadFailure) exit(1);
}

Future<void> _buildOpenSSL({
  required OS targetOS,
  required Architecture targetArchitecture,
  required Directory sharedOutputDirectory,
  required Directory openSslSrcDir,
}) async {
  final tmp = await Directory.systemTemp.createTemp('compile-openssl');

  final outputDirectory = Directory.fromUri(sharedOutputDirectory.uri
          .resolve('${targetOS.name}-${targetArchitecture.name}'))
      .absolute;

  // We configure the project from a separate folder per ABI, to support parallel builds

  final openSslBuildDirPath = tmp.path;

  // Absolute path of the Configure program in the src folder
  final String configureProgramPath =
      openSslSrcDir.absolute.uri.resolve('Configure').toFilePath();

  final configName = _resolveConfigName(
    targetOS,
    targetArchitecture,
  );
  if (targetOS == OS.android) {
    throw 'TODO: Android';
  }

  final extraConfigureArgs = <String>[
    '--prefix=${outputDirectory.path}',
    '--openssldir=${outputDirectory.path}',
    if (targetOS == OS.linux) ...[
      '-fPIC',
      '-ffunction-sections',
      '-fdata-sections',
      '-fvisibility=hidden',
    ],
  ];

  switch (OS.current) {
    case OS.windows:
      throw 'TODO: Windows';
    case OS.linux:
      // run ./Configure with the target OS and architecture
      await _run(
          'perl',
          [
            configureProgramPath,
            configName,
            ..._configArgs,
            ...extraConfigureArgs,
          ],
          workingDirectory: openSslBuildDirPath);

      // Build static libraries
      await _run(
          'make',
          [
            '-j',
            '${Platform.numberOfProcessors}',
          ],
          workingDirectory: openSslBuildDirPath);

      // Copy compiled libraries into output directory
      await _run(
          'make',
          [
            'install',
          ],
          workingDirectory: openSslBuildDirPath);

      break;
  }

  await tmp.delete(recursive: true);
}

Future<void> _run(String executable, List<String> args,
    {String? workingDirectory}) async {
  final proc = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
  );
  final exitCode = await proc.exitCode;

  if (exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      'Expected $executable ${args.join(' ')} to complete',
      exitCode,
    );
  }
}

String _resolveConfigName(OS os, Architecture architecture) {
  return switch ((os, architecture)) {
    (OS.android, Architecture.arm) => 'android-arm',
    (OS.android, Architecture.arm64) => 'android-arm64',
    (OS.android, Architecture.ia32) => 'android-x86',
    (OS.android, Architecture.x64) => 'android-x86_64',
    (OS.android, Architecture.riscv64) => 'android-riscv64',
    (OS.linux, Architecture.arm) => 'linux-armv4',
    (OS.linux, Architecture.arm64) => 'linux-aarch64',
    (OS.linux, Architecture.ia32) => 'linux-x86',
    (OS.linux, Architecture.x64) => 'linux-x86_64',
    (OS.linux, Architecture.riscv64) => 'linux64-riscv64',
    (OS.windows, Architecture.arm64) => 'VC-WIN64-ARM',
    (OS.windows, Architecture.ia32) => 'VC-WIN32',
    (OS.windows, Architecture.x64) => 'VC-WIN64A',
    _ => throw UnsupportedError(
        'Unsupported target combination: ${os.name}-${architecture.name}',
      ),
  };
}

const _configArgs = [
  'no-shared',
  'no-apps',
  'no-docs',
  'no-tests',
  'no-engine',
  'no-module',
  'no-ssl',
  'no-tls',
  'no-dtls',
  'no-comp',
  'no-legacy',
  'no-fips',
  'no-async',
  'no-aria',
  'no-bf',
  'no-blake2',
  'no-camellia',
  'no-cast',
  'no-chacha',
  'no-cmac',
  'no-des',
  'no-dh',
  'no-dsa',
  'no-ec',
  'no-ecdh',
  'no-ecdsa',
  'no-md4',
  'no-mdc2',
  'no-ocsp',
  'no-poly1305',
  'no-rc2',
  'no-rc4',
  'no-rc5',
  'no-rmd160',
  'no-seed',
  'no-siphash',
  'no-sm2',
  'no-sm3',
  'no-sm4',
  'no-srp',
  'no-ts',
  'no-whirlpool',
];

const _linuxArchitectures = [
  // TODO: Arm seems to cause crashes
  //Architecture.arm,
  Architecture.arm64,
  Architecture.ia32,
  Architecture.x64,
  Architecture.riscv64,
];
