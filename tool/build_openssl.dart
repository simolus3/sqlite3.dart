import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/native_toolchain/msvc.dart' as msvc;
import 'package:native_toolchain_c/src/tool/tool_resolver.dart';

/// Compiles static OpenSSL libraries.
///
/// To use this script:
///
///   1. Download an OpenSSL 3.x release to `openssl-src/`.
///   2. `dart tool/build_openssl.dart <linux | android | windows>`.
void main(List<String> args) async {
  final container = switch (Platform.environment) {
    {
      'CONTAINER_TOOL': final tool,
      'CONTAINER_NAME': final name,
      'CONTAINER_SRC': final src,
    } =>
      BuildContainer(tool: tool, name: name, srcRoot: .parse(src)),
    _ => null,
  };
  if (container != null) {
    print('Running build in ${container.name}');
  }

  final src = Directory('openssl-src');
  if (!await src.exists()) {
    print('Expected openssl-src to exist');
    exit(1);
  }

  final target = Directory('openssl-compiled');
  if (!await target.exists()) {
    await target.create(recursive: true);
  }

  var hadFailure = false;

  for (final platform in args) {
    final OS targetOS;
    final List<Architecture> targetArchs;

    switch (platform) {
      case 'linux':
        targetArchs = _linuxArchitectures;
        targetOS = OS.linux;
        break;
      case 'android':
        targetArchs = _androidArchitectures;
        targetOS = OS.android;
        break;
      case 'windows':
        targetArchs = _windowsArchitectures;
        targetOS = OS.windows;
        break;
      default:
        throw UnsupportedError(
          'Unsupported target OS, expected linux, windows or android.',
        );
    }

    for (final arch in targetArchs) {
      try {
        await _buildOpenSSL(
          targetOS: targetOS,
          targetArchitecture: arch,
          sharedOutputDirectory: target,
          openSslSrcDir: src,
          container: container,
        );
      } catch (e, s) {
        hadFailure = true;
        print('Build failed for $platform-$arch: $e');
        print(s);
      }
    }
  }

  if (hadFailure) exit(1);
}

Future<void> _buildOpenSSL({
  required OS targetOS,
  required Architecture targetArchitecture,
  required Directory sharedOutputDirectory,
  required Directory openSslSrcDir,
  BuildContainer? container,
}) async {
  final tmp = container != null
      ? null
      : await Directory.systemTemp.createTemp('compile-openssl');
  final String tmpPath;
  final String outputDirectory;
  final hostOutputDirectory = Directory.fromUri(
    sharedOutputDirectory.uri.resolve(
      '${targetOS.name}-${targetArchitecture.name}',
    ),
  );

  if (tmp == null) {
    final mktemp = await container!.start('mktemp', ['-d']);
    tmpPath = (await utf8.decodeStream(mktemp.stdout)).trim();

    outputDirectory = '/opt/openssl-${targetArchitecture.name}';
  } else {
    tmpPath = tmp.path;
    outputDirectory = hostOutputDirectory.absolute.path;
  }

  // We configure the project from a separate folder per ABI, to support parallel builds

  final openSslBuildDirPath = tmpPath;

  // Absolute path of the Configure program in the src folder
  final String configureProgramPath =
      (container != null ? container.srcRoot : openSslSrcDir.absolute.uri)
          .resolve('Configure')
          .toFilePath();

  final configName = _resolveConfigName(targetOS, targetArchitecture);

  final Map<String, String> extraEnv = {};
  if (targetOS == OS.android) {
    final String? ndkRoot = Platform.environment['ANDROID_NDK_ROOT'];

    if (ndkRoot == null) {
      throw Exception('Android NDK not found. Set ANDROID_NDK_ROOT');
    }

    final existingPath = Platform.environment['PATH'] ?? '';
    extraEnv['PATH'] =
        '$ndkRoot/toolchains/llvm/prebuilt/linux-x86_64/bin:$existingPath';
  }

  final extraConfigureArgs = <String>[
    '--prefix=${outputDirectory}',
    '--openssldir=${outputDirectory}',
    if (targetOS == OS.linux) ...[
      '-fPIC',
      '-ffunction-sections',
      '-fdata-sections',
      '-fvisibility=hidden',
      '--cross-compile-prefix=${_linuxCrossCompilePrefix(targetArchitecture)}',
    ],
  ];

  switch (OS.current) {
    case OS.windows:
      extraEnv.addAll(await _resolveWindowsBuildConfig(targetArchitecture));

      await _run(
        'perl',
        [
          configureProgramPath,
          configName,
          ..._configArgs,
          ...extraConfigureArgs,
        ],
        workingDirectory: openSslBuildDirPath,
        environment: extraEnv,
      );

      // Build static libraries
      await _run(
        'nmake',
        [],
        inShell: true,
        workingDirectory: openSslBuildDirPath,
        environment: extraEnv,
      );

      // Copy compiled libraries into output directory
      await _run(
        'nmake',
        ['install'],
        inShell: true,
        workingDirectory: openSslBuildDirPath,
        environment: extraEnv,
      );
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
        workingDirectory: openSslBuildDirPath,
        environment: extraEnv,
        container: container,
      );

      // Build static libraries
      await _run(
        'make',
        ['-j', '${Platform.numberOfProcessors}'],
        workingDirectory: openSslBuildDirPath,
        environment: extraEnv,
        container: container,
      );

      // Copy compiled libraries into output directory
      await _run(
        'make',
        ['install'],
        workingDirectory: openSslBuildDirPath,
        environment: extraEnv,
        container: container,
      );

      break;
  }

  if (container != null) {
    print('Copying results from ${container.name}:$outputDirectory');

    await _run(container.tool, [
      'container',
      'cp',
      '${container.name}:$outputDirectory',
      hostOutputDirectory.path,
    ]);
  }

  await tmp?.delete(recursive: true);
}

Future<Map<String, String>> _resolveWindowsBuildConfig(
  Architecture arch,
) async {
  final vcvars = switch (arch) {
    Architecture.arm64 => msvc.vcvarsarm64,
    Architecture.ia32 => msvc.vcvars32,
    Architecture.x64 => msvc.vcvars64,
    _ => throw ArgumentError.value(arch),
  };

  final resolved = await vcvars.defaultResolver!.resolve(
    ToolResolvingContext(logger: null),
  );
  return await environmentFromBatchFile(resolved.first.uri);
}

Future<void> _run(
  String executable,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool inShell = false,
  BuildContainer? container,
}) async {
  print('Running $executable $args');

  final proc = switch (container) {
    null => await Process.start(
      executable,
      args,
      runInShell: inShell,
      mode: .inheritStdio,
      workingDirectory: workingDirectory,
      environment: environment,
    ),
    final container => await container.start(
      executable,
      args,
      mode: .inheritStdio,
      workingDirectory: workingDirectory,
      environment: environment,
    ),
  };

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

/// A container running the build.
///
/// The container must already have relevant build tools installed, this script
/// then runs its commands in the container.
final class BuildContainer({
  /// The CLI tool to interact with containers, e.g. `podman`.
  required final String tool,

  /// The name of the container.
  required final String name,

  /// The location in the container where `openssl-src` is mounted.
  required final Uri srcRoot,
}) {
  Future<Process> start(
    String executable,
    List<String> args, {
    ProcessStartMode mode = .normal,
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.start(tool, [
      'exec',
      if (environment != null)
        for (final entry in environment.entries) ...[
          '-e',
          '${entry.key}=${entry.value}',
        ],
      if (workingDirectory != null) '--workdir=$workingDirectory',
      name,
      executable,
      ...args,
    ], mode: mode);
  }
}

// Disable features we don't need for SQLCipher.
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

String _linuxCrossCompilePrefix(Architecture architecture) {
  return switch (architecture) {
    Architecture.arm => 'arm-linux-gnueabihf-',
    Architecture.arm64 => 'aarch64-linux-gnu-',
    Architecture.x64 => 'x86_64-linux-gnu-',
    Architecture.ia32 => 'i686-linux-gnu-',
    Architecture.riscv64 => 'riscv64-linux-gnu-',
    _ => throw ArgumentError('Unhandled architecture'),
  };
}

const _linuxArchitectures = [
  Architecture.arm,
  Architecture.arm64,
  Architecture.ia32,
  Architecture.x64,
  Architecture.riscv64,
];

const _androidArchitectures = [
  Architecture.arm,
  Architecture.arm64,
  Architecture.ia32,
  Architecture.x64,
];

const _windowsArchitectures = [
  Architecture.ia32,
  Architecture.x64,
  Architecture.arm64,
];
