import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart';
import 'package:sqlite3/src/hook/android_ndk.dart';

// Based from https://github.com/LucazzP/openssl_dart

// Build instructions: https://github.com/openssl/openssl/blob/openssl-3.6.2/INSTALL.md#building-openssl

const configArgs = [
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

const perlDownloadUrl =
    'https://strawberryperl.com/download/5.14.2.1/strawberry-perl-5.14.2.1-64bit-portable.zip';
const jomDownloadUrl =
    'https://download.qt.io/official_releases/jom/jom_1_1_5.zip';

Map<String, String> environment = {};

Future<Directory?> buildOpenSSL(
  BuildInput input,
  BuildOutputBuilder output, {
  required Directory openSslSrcDir,
}) async {
  if (!input.config.buildCodeAssets) return null;

  final workDir = input.outputDirectory;

  // We configure the project from a separate folder per ABI, to support parallel builds
  final openSslBuildDir = Directory(
    workDir.resolve('build-openssl').toFilePath(windows: Platform.isWindows),
  )..createSync(recursive: true);

  final openSslBuildDirUri = openSslBuildDir.uri;

  // Directory where we install the OpenSSL binaries
  final outputDir = join(
    input.outputDirectoryShared.toFilePath(windows: Platform.isWindows),
    'openssl',
  );

  // Absolute path of the Configure program in the src folder
  final String configureProgramPath = join(openSslSrcDir.path, 'Configure');

  final configName = resolveConfigName(
    input.config.code.targetOS,
    input.config.code.targetArchitecture,
    input.config.code.targetOS == OS.iOS
        ? input.config.code.iOS.targetSdk
        : null,
  );
  if (input.config.code.targetOS == OS.android) {
    final ndkRoot = await resolveAndroidNdkRoot();
    environment['ANDROID_NDK_ROOT'] = ndkRoot;
    environment['ANDROID_NDK_HOME'] = ndkRoot;

    final toolchainBin = resolveAndroidToolchainBinDir(ndkRoot);
    final existingPath = Platform.environment['PATH'] ?? '';
    final pathSeparator = Platform.isWindows ? ';' : ':';
    environment['PATH'] = '$toolchainBin$pathSeparator$existingPath';

    // print(environment);
  }

  final extraConfigureArgs = <String>[
    '--prefix=$outputDir',
    '--openssldir=$outputDir',
    if (input.config.code.targetOS == OS.linux) ...[
      '-fPIC',
      '-ffunction-sections',
      '-fdata-sections',
      '-fvisibility=hidden',
    ],
    if (input.config.code.targetOS == OS.macOS ||
        input.config.code.targetOS == OS.iOS) ...[
      '-Wl,-headerpad_max_install_names',
    ],
  ];

  switch (OS.current) {
    case OS.windows:
      final msvcEnv = await resolveWindowsBuildEnvironment(
        input.config.code.targetArchitecture,
      );
      // should have perl and jom installed
      final needDownloadPerl = !await isProgramInstalled('perl');
      final needDownloadJom = !await isProgramInstalled('jom');
      var perlProgram = 'perl';
      var jomProgram = 'jom';

      if (needDownloadPerl) {
        await downloadAndExtract(perlDownloadUrl, 'perl.zip', workDir);
        perlProgram = workDir
            .resolve('./perl/perl/bin/perl.exe')
            .toFilePath(windows: Platform.isWindows);
      }
      if (needDownloadJom) {
        await downloadAndExtract(jomDownloadUrl, 'jom.zip', workDir);
        jomProgram = workDir
            .resolve('./jom/jom.exe')
            .toFilePath(windows: Platform.isWindows);
      }

      // run ./Configure with the target OS and architecture
      await runProcess(
        perlProgram,
        [
          configureProgramPath,
          configName,
          ...configArgs,
          ...extraConfigureArgs,
          // needed to build using multiple threads on Windows
          '/FS',
        ],
        workingDirectory: openSslBuildDirUri,
        extraEnvironment: msvcEnv,
      );

      // run jom to build the library
      await runProcess(
        jomProgram,
        ['-j', '${Platform.numberOfProcessors}'],
        workingDirectory: openSslBuildDirUri,
        extraEnvironment: msvcEnv,
      );

      // delete perl and jom if downloaded
      if (needDownloadPerl) {
        await Directory(
          workDir.resolve('perl').toFilePath(windows: Platform.isWindows),
        ).delete(recursive: true);
      }
      if (needDownloadJom) {
        await Directory(
          workDir.resolve('jom').toFilePath(windows: Platform.isWindows),
        ).delete(recursive: true);
      }
      break;
    case OS.macOS:
    case OS.linux:
      final hasPerl = await isProgramInstalled('perl');
      if (!hasPerl) {
        throw Exception(
          'perl is not installed, please install it to be able to build openssl.',
        );
      }

      // run ./Configure with the target OS and architecture
      await runProcess(configureProgramPath, [
        configName,
        ...configArgs,
        ...extraConfigureArgs,
      ], workingDirectory: openSslBuildDirUri);

      // run make
      await runProcess('make', [
        '-j',
        '${Platform.numberOfProcessors}',
      ], workingDirectory: openSslBuildDirUri);

      await runProcess('make', [
        'install',
      ], workingDirectory: openSslBuildDirUri);

      break;
  }

  return Directory(outputDir);
}

String getStaticCryptoLib(
  Directory opensslDir,
  OS targetOS,
  Architecture targetArch,
) {
  final libName = switch ((targetOS, LinkModePreference.static)) {
    (
      OS.windows,
      LinkModePreference.static || LinkModePreference.preferStatic,
    ) =>
      'libcrypto_static.lib',
    (
      OS.macOS || OS.iOS,
      LinkModePreference.static || LinkModePreference.preferStatic,
    ) =>
      'libcrypto.a',
    (
      OS.linux || OS.android,
      LinkModePreference.static || LinkModePreference.preferStatic,
    ) =>
      'libcrypto.a',
    (
      OS.windows,
      LinkModePreference.dynamic || LinkModePreference.preferDynamic,
    ) =>
      'libcrypto-3-${targetArch.name}.dll',
    (
      OS.macOS || OS.iOS,
      LinkModePreference.dynamic || LinkModePreference.preferDynamic,
    ) =>
      'libcrypto.dylib',
    (
      OS.linux || OS.android,
      LinkModePreference.dynamic || LinkModePreference.preferDynamic,
    ) =>
      'libcrypto.so',
    _ => throw UnsupportedError('Unsupported target OS: $targetOS'),
  };

  final String openSSLLibDir;
  if (Directory(join(opensslDir.path, 'lib')).existsSync()) {
    openSSLLibDir = join(opensslDir.path, 'lib');
  } else {
    openSSLLibDir = join(opensslDir.path, 'lib64');
  }

  final libPath = join(openSSLLibDir, libName);
  if (!File(libPath).existsSync()) {
    throw Exception(
      'Could not find OpenSSL static library in '
      '$libPath',
    );
  }

  return libPath;
}

Future<bool> isProgramInstalled(String programName) async {
  try {
    await runProcess(programName, []);
    return true;
  } catch (e) {
    return false;
  }
}

String resolveConfigName(OS os, Architecture architecture, IOSSdk? iosSdk) {
  final isIosSimulator = iosSdk == IOSSdk.iPhoneSimulator;
  return switch ((os, architecture)) {
    (OS.android, Architecture.arm) => 'android-arm',
    (OS.android, Architecture.arm64) => 'android-arm64',
    (OS.android, Architecture.ia32) => 'android-x86',
    (OS.android, Architecture.x64) => 'android-x86_64',
    (OS.android, Architecture.riscv64) => 'android-riscv64',

    (OS.iOS, Architecture.arm) => 'ios-xcrun',
    (OS.iOS, Architecture.arm64) =>
      isIosSimulator ? 'iossimulator-arm64-xcrun' : 'ios64-xcrun',
    (OS.iOS, Architecture.ia32) => 'iossimulator-i386-xcrun',
    (OS.iOS, Architecture.x64) => 'iossimulator-x86_64-xcrun',

    (OS.macOS, Architecture.arm64) => 'darwin64-arm64',
    (OS.macOS, Architecture.x64) => 'darwin64-x86_64',
    (OS.macOS, Architecture.ia32) => 'darwin-i386',

    (OS.linux, Architecture.arm) => 'linux-armv4',
    (OS.linux, Architecture.arm64) => 'linux-aarch64',
    (OS.linux, Architecture.ia32) => 'linux-x86',
    (OS.linux, Architecture.x64) => 'linux-x86_64',
    (OS.linux, Architecture.riscv32) => 'linux32-riscv32',
    (OS.linux, Architecture.riscv64) => 'linux64-riscv64',

    (OS.windows, Architecture.arm) => 'VC-WIN32-ARM',
    (OS.windows, Architecture.arm64) => 'VC-WIN64-ARM',
    (OS.windows, Architecture.ia32) => 'VC-WIN32',
    (OS.windows, Architecture.x64) => 'VC-WIN64A',

    _ => throw UnsupportedError(
      'Unsupported target combination: ${os.name}-${architecture.name}',
    ),
  };
}

Future<Map<String, String>> resolveWindowsBuildEnvironment(
  Architecture architecture,
) async {
  final result = await runProcess('cmd.exe', [
    '/c',
    r'call C:\"Program Files"\"Microsoft Visual Studio"\2022\Community\VC\Auxiliary\Build\vcvars64.bat >nul && set',
  ]);

  return Map.fromEntries(
    result.trim().split('\n').map((line) {
      final parts = line.split('=');
      if (parts.length != 2) {
        return null;
      }
      return MapEntry(parts[0].trim(), parts[1].trim());
    }).nonNulls,
  );
}

Future<String> runProcess(
  String executable,
  List<String> arguments, {
  Uri? workingDirectory,
  Map<String, String>? extraEnvironment,
}) async {
  final processResult = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory?.toFilePath(windows: Platform.isWindows),
    environment: {...?extraEnvironment, ...environment},
    includeParentEnvironment: true,
  );
  print(processResult.stdout);
  if ((processResult.stderr as String).isNotEmpty) {
    print(processResult.stderr);
  }
  if (processResult.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      processResult.stderr.toString(),
      processResult.exitCode,
    );
  }
  return processResult.stdout.toString();
}

Future<void> downloadAndExtract(
  String url,
  String outputFileName,
  Uri workDir, {
  bool createFolderForExtraction = true,
}) async {
  // download the file
  await runProcess('curl', [
    '-L',
    url,
    '-o',
    outputFileName,
  ], workingDirectory: workDir);

  final fileOut = await runProcess('file', [
    outputFileName,
  ], workingDirectory: workDir);
  print(fileOut);

  // unzip the file
  final isTarGz = outputFileName.endsWith('.tar.gz');
  final isTarXz = outputFileName.endsWith('.tar.xz');
  final destinationPath = workDir.resolve(
    outputFileName
        .replaceAll('.tar.gz', '')
        .replaceAll('.zip', '')
        .replaceAll('.tar.xz', ''),
  );
  print("destination $destinationPath");
  await Directory(
    destinationPath.toFilePath(windows: Platform.isWindows),
  ).create(recursive: true);
  await runProcess('tar', [
    isTarGz ? '-xzf' : (isTarXz ? '-xJf' : '-xf'),
    outputFileName,
    if (createFolderForExtraction) ...[
      '-C',
      destinationPath.toFilePath(windows: Platform.isWindows),
    ],
  ], workingDirectory: workDir);

  // remove the tar.gz file
  await File(
    workDir.resolve(outputFileName).toFilePath(windows: Platform.isWindows),
  ).delete();
}
