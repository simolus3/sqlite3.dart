import 'dart:convert';
import 'dart:io';

import 'package:pool/pool.dart';

final _compileTasks = Pool(Platform.numberOfProcessors);

final defines = const LineSplitter()
    .convert(_defaultDefines)
    .map((line) => line.trim())
    .map((line) => '-D$line')
    .toList();

void main(List<String> args) async {
  await Directory('out').create();

  Future<void> compileAll(List<Future<void> Function()> compile) {
    return Future.wait([
      for (final task in compile) _compileTasks.withResource(() => task()),
    ], eagerError: true);
  }

  if (Platform.isLinux) {
    await compileAll([
      for (final (compiler, abi) in _linuxAbis)
        for (final sqlite3mc in [false, true])
          () => _compileLinux(compiler, abi, sqlite3mc)
    ]);
  } else if (Platform.isMacOS) {
    await compileAll([
      for (final sqlite3mc in [false, true]) ...[
        for (final (triple, name) in _appleAbis)
          () => _compileApple(triple, name, sqlite3mc),
        for (final (triple, name) in _androidAbis)
          () => _compileAndroid(triple, name, sqlite3mc)
      ]
    ]);
  } else if (Platform.isWindows) {
    final abiName = switch (args.single) {
      'amd64' => 'x64',
      'amd64_x86' => 'x86',
      'amd64_arm64' => 'aarch64',
      _ => throw ArgumentError('Unknown abi: ${args.single}'),
    };
    final defines = const LineSplitter()
        .convert(_defaultDefines)
        .map((line) => line.trim())
        .map((line) => '/D$line');

    for (final sqlite3Ciphers in [false, true]) {
      final args = [
        '/LD',
        sqlite3Ciphers
            ? r'sqlite3-src\sqlite3mc\sqlite3mc_amalgamation.c'
            : r'sqlite3-src\sqlite3\sqlite3.c',
        '/DSQLITE_API=__declspec(dllexport)',
        '/O2',
        ...defines,
        '/I',
        sqlite3Ciphers ? r'sqlite3-src\sqlite3mc' : 'sqlite3-src\sqlite3',
        '/Fe:out\\win-$abiName-sqlite3${sqlite3Ciphers ? 'mc' : ''}.dll'
      ];

      print('Running cl ${args.join(' ')}');
      final result = await Process.run('cl', args);
      if (result.exitCode != 0) {
        throw 'Compiling for $abiName (ciphers: $sqlite3Ciphers) failed: ${result.stdout}\n ${result.stderr}';
      }
    }
  }
}

Future<void> _compileLinux(
    String compiler, String abi, bool sqlite3Ciphers) async {
  if (abi == 'x86' && sqlite3Ciphers) {
    // i686 does not support sqlite ciphers.
    return;
  }

  final args = [
    '-fPIC',
    '-shared',
    '-O3',
    ...defines,
    sqlite3Ciphers
        ? 'sqlite3-src/sqlite3mc/sqlite3mc_amalgamation.c'
        : 'sqlite3-src/sqlite3/sqlite3.c',
    '-I',
    sqlite3Ciphers ? 'sqlite3-src/sqlite3mc/' : 'sqlite3-src/sqlite3',
    '-o',
    'out/linux-$abi-sqlite3${sqlite3Ciphers ? 'mc' : ''}.so',
  ];

  print('Running $compiler ${args.join(' ')}');
  final result = await Process.run(compiler, args);

  if (result.exitCode != 0) {
    throw 'Compiling for $abi (ciphers: $sqlite3Ciphers) failed: ${result.stdout}\n ${result.stderr}';
  }
}

Future<void> _compileApple(
    String triple, String prefix, bool sqlite3Ciphers) async {
  await _clangCompile(
    'clang',
    triple,
    sqlite3Ciphers,
    '$prefix-sqlite3${sqlite3Ciphers ? 'mc' : ''}.dylib',
    additionalArgs: ['-Wl,-headerpad_max_install_names'],
  );
}

Future<void> _compileAndroid(
    String triple, String abiName, bool sqlite3Ciphers) async {
  // https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md#environment-variables-1
  final ndk28 = Platform.environment['ANDROID_NDK_LATEST_HOME']!;
  final clang = '$ndk28/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang';

  await _clangCompile(
    clang,
    triple,
    sqlite3Ciphers,
    'android-$abiName-sqlite3${sqlite3Ciphers ? 'mc' : ''}.so',
  );
}

Future<void> _clangCompile(
    String executable, String triple, bool sqlite3Ciphers, String filename,
    {List<String> additionalArgs = const []}) async {
  final args = [
    '-target',
    triple,
    '-fPIC',
    '-shared',
    '-O3',
    ...defines,
    ...additionalArgs,
    sqlite3Ciphers
        ? 'sqlite3-src/sqlite3mc/sqlite3mc_amalgamation.c'
        : 'sqlite3-src/sqlite3/sqlite3.c',
    '-I',
    sqlite3Ciphers ? 'sqlite3-src/sqlite3mc/' : 'sqlite3-src/sqlite3',
    '-o',
    'out/$filename',
  ];

  print('Running $executable ${args.join(' ')}');
  final result = await Process.run(executable, args);

  if (result.exitCode != 0) {
    throw 'Compiling for $triple (ciphers: $sqlite3Ciphers) failed: ${result.stdout}\n ${result.stderr}';
  }
}

const _linuxAbis = [
  ('x86_64-linux-gnu-gcc', 'x64'),
  ('i686-linux-gnu-gcc', 'x86'),
  ('aarch64-linux-gnu-gcc', 'aarch64'),
  ('arm-linux-gnueabihf-gcc', 'armv7'),
  ('riscv64-linux-gnu-gcc', 'riscv64gc'),
];

const _appleAbis = [
  ('aarch64-apple-macos', 'macos-aarch64'),
  ('x86_64-apple-macos', 'macos-x64'),
  ('x86_64-apple-ios13.0-simulator', 'ios-sim-x64'),
  ('arm64-apple-ios13.0-simulator', 'ios-sim-aarch64'),
  ('arm64-apple-ios13.0', 'ios-aarch64'),
];

const _androidAbis = [
  ('armv7a-linux-androideabi24', 'armv7a'),
  ('aarch64-linux-android24', 'aarch64'),
  ('i686-linux-android24', 'x86'),
  ('x86_64-linux-android24', 'x64'),
];

// Keep in sync with sqlite3/lib/src/hook/description.dart
const _defaultDefines = '''
  SQLITE_ENABLE_DBSTAT_VTAB
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_RTREE
  SQLITE_ENABLE_MATH_FUNCTIONS
  SQLITE_DQS=0
  SQLITE_DEFAULT_MEMSTATUS=0
  SQLITE_TEMP_STORE=2
  SQLITE_MAX_EXPR_DEPTH=0
  SQLITE_STRICT_SUBTYPE=1
  SQLITE_OMIT_AUTHORIZATION
  SQLITE_OMIT_DECLTYPE
  SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_PROGRESS_CALLBACK
  SQLITE_OMIT_SHARED_CACHE
  SQLITE_OMIT_TCL_VARIABLE
  SQLITE_OMIT_TRACE
  SQLITE_USE_ALLOCA
  SQLITE_ENABLE_SESSION
  SQLITE_ENABLE_PREUPDATE_HOOK
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_HAVE_LOCALTIME_R
  SQLITE_HAVE_LOCALTIME_S
  SQLITE_HAVE_MALLOC_USABLE_SIZE
  SQLITE_HAVE_STRCHRNUL
''';
