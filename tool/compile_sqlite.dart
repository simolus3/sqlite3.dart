import 'dart:convert';
import 'dart:io';

final defines = const LineSplitter()
    .convert(_defaultDefines)
    .map((line) => line.trim())
    .map((line) => '-D$line')
    .toList();

void main() async {
  await Directory('out').create();

  if (Platform.isLinux) {
    await Future.wait([
      for (final (compiler, abi) in _linuxAbis)
        for (final sqlite3mc in [false, true])
          _compileLinux(compiler, abi, sqlite3mc)
    ], eagerError: true);
  }
}

Future<void> _compileLinux(
    String compiler, String abi, bool sqlite3Ciphers) async {
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

const _linuxAbis = [
  ('x86_64-linux-gnu-gcc', 'x64'),
  ('i686-linux-gnu-gcc', 'x86'),
  ('aarch64-linux-gnu-gcc', 'aarch64'),
  ('arm-linux-gnueabihf-gcc', 'armv7'),
  ('riscv64-linux-gnu-gcc', 'riscv64gc'),
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
