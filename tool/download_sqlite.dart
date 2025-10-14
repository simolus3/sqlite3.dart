import 'dart:io';

const sqlitePath = 'sqlite-amalgamation-3500400';
const sqliteSource = 'https://sqlite.org/2025/$sqlitePath.zip';
const sqliteMultipleCiphersSource =
    'https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.2.4/sqlite3mc-2.2.4-sqlite-3.50.4-amalgamation.zip';

const tmpDir = 'tmp';

void main(List<String> args) async {
  await Directory(tmpDir).create();

  await _downloadAndExtract(sqliteSource, 'sqlite3');
  await _downloadAndExtract(sqliteMultipleCiphersSource, 'sqlite3mc');

  await Directory('out').create();
  await Directory('out/sqlite3mc').create();
  await File('$tmpDir/sqlite3mc_amalgamation.h')
      .copy('out/sqlite3mc/sqlite3mc_amalgamation.h');
  await File('$tmpDir/sqlite3mc_amalgamation.c')
      .copy('out/sqlite3mc/sqlite3mc_amalgamation.c');

  await Directory('out/sqlite3').create();
  await File('$tmpDir/$sqlitePath/sqlite3.h').copy('out/sqlite3/sqlite3.h');
  await File('$tmpDir/$sqlitePath/sqlite3.c').copy('out/sqlite3/sqlite3.c');
  await File('$tmpDir/$sqlitePath/sqlite3ext.h')
      .copy('out/sqlite3/sqlite3ext.h');
}

Future<void> _downloadAndExtract(String url, String filename) async {
  await _run('curl -L $url --output $filename.zip', workingDirectory: tmpDir);
  await _run('unzip $filename.zip', workingDirectory: tmpDir);
}

Future<void> _run(String command, {String? workingDirectory}) async {
  print('Running $command');

  final proc = await Process.start(
    'sh',
    ['-c', command],
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
  );
  final exitCode = await proc.exitCode;

  if (exitCode != 0) {
    exit(exitCode);
  }
}
