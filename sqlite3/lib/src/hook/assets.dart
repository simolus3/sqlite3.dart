import 'package:code_assets/code_assets.dart';

import 'asset_hashes.dart';

enum LibraryType {
  /// SQLite build, with sources taken from https://sqlite.org/download.html.
  sqlite3,

  /// SQLite multiple ciphers build, with sources taken from
  /// https://github.com/utelle/SQLite3MultipleCiphers.
  sqlite3mc;

  String get basename => switch (this) {
    LibraryType.sqlite3 => 'sqlite3',
    LibraryType.sqlite3mc => 'sqlite3mc',
  };

  String filename(CodeConfig config) {
    final basename = this.basename;
    return switch (config.targetOS) {
      OS.windows => '$basename.dll',
      OS.iOS || OS.macOS => 'lib$basename.dylib',
      OS.android || OS.linux || _ => 'lib$basename.so',
    };
  }
}

enum TargetOperatingSystem {
  windows(OS.windows),
  macos(OS.macOS),
  linux(OS.linux),
  ios(OS.iOS),
  iosSimulator(OS.iOS, customName: 'ios_sim'),
  android(OS.android),
  unknown(OS.linux, customName: 'unknown');

  final OS hookOS;
  final String? _nameOverride;

  const TargetOperatingSystem(this.hookOS, {String? customName})
    : _nameOverride = customName;

  String get name => _nameOverride ?? hookOS.name;

  static TargetOperatingSystem forConfig(CodeConfig config) {
    return switch (config.targetOS) {
      OS.windows => windows,
      OS.macOS => macos,
      OS.linux => linux,
      OS.iOS when config.iOS.targetSdk == IOSSdk.iPhoneOS => ios,
      OS.iOS when config.iOS.targetSdk == IOSSdk.iPhoneSimulator =>
        iosSimulator,
      OS.android => android,
      _ => unknown,
    };
  }
}

final class PrebuiltSqliteLibrary {
  /// The operating system this library has been compiled for.
  final TargetOperatingSystem os;

  /// The target architecture this library has been compiled for.
  final Architecture architecture;

  /// The built library (sqlite3 or sqlite3mc).
  final LibraryType type;

  PrebuiltSqliteLibrary({
    required this.os,
    required this.architecture,
    required this.type,
  });

  bool get isSupported {
    final architectures = _supportedAbis[os];
    if (architectures == null || !architectures.contains(architecture)) {
      return false;
    }

    // Compiling sqlite3mc fails for i686 linux builds, so report that as not
    // supported.
    final unsupportedCiphersBuild =
        os == TargetOperatingSystem.linux &&
        architecture == Architecture.ia32 &&
        type == LibraryType.sqlite3mc;
    return !unsupportedCiphersBuild;
  }

  String get filename {
    if (!isSupported) {
      throw StateError('Unsupported binary does not have a filename');
    }

    return os.hookOS.dylibFileName(
      '${type.basename}.${architecture.name}.${os.name}',
    );
  }

  /// The directory under [HookInput.outputDirectoryShared] used to download
  /// this library.
  ///
  /// There's a test asserting that this is unique for all valid values.
  String get dirname => 'download-${hashCode.toRadixString(16)}';

  @override
  int get hashCode => Object.hash(
    os,
    // Note: Architecture does not have a stable hash code, so we hash its
    // name instead.
    architecture.name,
    type,
    // This is a constant, but if affects the dirname we want for hook
    // invocations.
    releaseTag,
  );

  @override
  bool operator ==(Object other) {
    return other is PrebuiltSqliteLibrary &&
        other.os == os &&
        other.architecture == architecture &&
        other.type == type;
  }

  void checkSupported() {
    if (!isSupported) {
      throw UnsupportedError(
        'There is no pre-compiled sqlite3 library for this target. '
        'Please file an issue on https://github.com/simolus3/sqlite3.dart or '
        'use a custom build.',
      );
    }
  }

  /// Finds the library instace for the target requested in [CodeConfig].
  static PrebuiltSqliteLibrary resolve(CodeConfig config, LibraryType type) {
    return PrebuiltSqliteLibrary(
      os: TargetOperatingSystem.forConfig(config),
      architecture: config.targetArchitecture,
      type: type,
    );
  }

  /// All prebuilt sqlite3 libraries attached to GH releases.
  static Iterable<PrebuiltSqliteLibrary> get all sync* {
    for (final MapEntry(key: os, value: abis) in _supportedAbis.entries) {
      for (final abi in abis) {
        for (final product in LibraryType.values) {
          final built = PrebuiltSqliteLibrary(
            os: os,
            architecture: abi,
            type: product,
          );
          if (built.isSupported) {
            yield built;
          }
        }
      }
    }
  }

  static const _supportedAbis = {
    TargetOperatingSystem.linux: [
      Architecture.ia32,
      Architecture.x64,
      Architecture.riscv64,
      Architecture.arm,
      Architecture.arm64,
    ],
    TargetOperatingSystem.windows: [
      Architecture.ia32,
      Architecture.x64,
      Architecture.arm64,
    ],
    TargetOperatingSystem.macos: [Architecture.x64, Architecture.arm64],
    TargetOperatingSystem.ios: [Architecture.arm64],
    TargetOperatingSystem.iosSimulator: [Architecture.x64, Architecture.arm64],
    TargetOperatingSystem.android: [
      Architecture.ia32,
      Architecture.x64,
      Architecture.riscv64,
      Architecture.arm,
      Architecture.arm64,
    ],
  };
}
