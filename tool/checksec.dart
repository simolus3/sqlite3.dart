import 'dart:convert';
import 'dart:io';

/// Runs [checksec](https://github.com/slimm609/checksec/) on binaries we
/// atttach to `sqlite3` and `sqlite3_connection_pool` releases.
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart tool/checksec.dart <file>');
    exit(1);
  }

  final tmp = await Directory.systemTemp.createTemp('dart-sqlite-checksec');
  final file = File.fromUri(tmp.uri.resolve('list.txt'));
  await file.writeAsString(
    args.map((path) => File(path).absolute.path).join(Platform.lineTerminator),
  );

  final output = await Process.run('checksec', [
    'listfile',
    file.path,
    '--output=json',
  ], stdoutEncoding: null);
  await tmp.delete(recursive: true);
  final decoded =
      json.fuse(systemEncoding).decode(output.stdout as List<int>)
          as List<Object?>;
  final failedChecks = <String>[];

  for (final entry in decoded) {
    entry as Map<String, Object?>;

    final file = entry['name'] as String;
    final checks = entry['checks'] as Map<String, Object?>;

    void check(String key, {bool allowYellow = false}) {
      final {'value': value, 'status': status} =
          checks[key] as Map<String, Object?>;

      if (status == 'unset' ||
          status == 'green' ||
          (allowYellow && status == 'yellow')) {
        return;
      }

      failedChecks.add('$file: Check $key failed with $value ($status)');
    }

    check('relro');
    check('canary');
    check('nx');
    check('rpath');
    check('runpath', allowYellow: true);
    check('separate_code');
    check('fortify_source');
  }

  if (failedChecks.isEmpty) {
    print('No issues found in ${args.join(' ')}');
  } else {
    for (final failed in failedChecks) {
      print(failed);
    }

    exit(1);
  }
}
