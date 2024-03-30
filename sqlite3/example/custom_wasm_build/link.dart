import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    print("Usage: dart link.dart target/wasm32-wasi/<buildtype>");
  }

  final directory = Directory(args[0]);
  final entries = <String>[];

  for (final entry in directory.listSync()) {
    if (entry.path.endsWith('.o') || entry.path.endsWith('.a')) {
      entries.add(entry.path);
    }
  }

  final process = Process.runSync('clang', [
    '--target=wasm32-unknown-wasi',
    '--sysroot=/usr/share/wasi-sysroot',
    '-flto',
    ...entries,
    '-o',
    'sqlite3.wasm',
    '-nostartfiles',
    '-Wl,--no-entry',
    '-Wl,--export-dynamic',
    '-Wl,--import-memory',
    '-v',
  ]);

  if (process.exitCode != 0) {
    print(
        'Could not link: ${process.exitCode}, ${process.stderr}, ${process.stdout}');
  }
}
