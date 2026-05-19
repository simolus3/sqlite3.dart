// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_toolchain_c/src/native_toolchain/android_ndk.dart'
    as ntc_ndk;
import 'package:native_toolchain_c/src/tool/tool_instance.dart';
import 'package:native_toolchain_c/src/tool/tool_resolver.dart';

/// Resolve the Android NDK root, picking the latest installed version.
/// Uses the native_toolchain_cmake resolver first, then falls back to a local scan.
Future<String> resolveAndroidNdkRoot() async {
  try {
    final resolver = ntc_ndk.androidNdk.defaultResolver;
    if (resolver != null) {
      final instances = await resolver.resolve(
        ToolResolvingContext(logger: Logger.detached('android_ndk')),
      );
      final ndkInstance = _pickNdkInstance(instances);
      final ndkPath = Directory.fromUri(ndkInstance.uri).path;
      if (await Directory(ndkPath).exists()) {
        return ndkPath;
      }
    }
  } catch (_) {
    // fall through to legacy resolution
  }
  throw Exception(
    'Android NDK not found. Set ANDROID_NDK_ROOT or install it via Android Studio (SDK Manager > NDK).',
  );
}

ToolInstance _pickNdkInstance(List<ToolInstance> instances) {
  final ndkInstances = instances
      .where((i) => i.tool.name == ntc_ndk.androidNdk.name)
      .toList();
  if (ndkInstances.isEmpty) {
    throw StateError('No Android NDK instance resolved');
  }

  ndkInstances.sort(
    (a, b) => switch ((a.version, b.version)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (_, _) => -a.version!.compareTo(b.version!),
    },
  );

  return ndkInstances.first;
}

String resolveAndroidToolchainBinDir(String ndkRoot) {
  // Android NDK toolchain binaries live under toolchains/llvm/prebuilt/<host>/bin.
  // Pick the first host tag that exists for the current platform.
  final hostTags = switch (Platform.operatingSystem) {
    'macos' => const ['darwin-x86_64', 'darwin-arm64'],
    'linux' => const ['linux-x86_64'],
    'windows' => const ['windows-x86_64', 'windows-arm64'],
    final os => throw UnsupportedError(
      'Unsupported host OS for Android NDK: $os',
    ),
  };

  for (final host in hostTags) {
    final binDir = Directory('$ndkRoot/toolchains/llvm/prebuilt/$host/bin');
    if (binDir.existsSync()) {
      return binDir.path;
    }
  }

  throw StateError(
    'Android NDK toolchain bin directory not found under '
    '$ndkRoot/toolchains/llvm/prebuilt for host ${Platform.operatingSystem}.',
  );
}
