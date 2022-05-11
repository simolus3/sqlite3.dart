import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  // Regular test driver isn't working, so this is what we do.
  final flutterArgs = [
    'run',
    '--target=test_driver/integration.dart',
    if (args.contains('linux')) ...['-d', 'linux'],
    if (args.contains('windows')) ...['-d', 'windows'],
  ];
  print('Running flutter $flutterArgs');
  final process = await Process.start('flutter', flutterArgs);

  var isSuccessful = false;

  process.stderr.pipe(stderr);
  final outputSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (line.contains('All tests passed!')) {
      isSuccessful = true;
      process.kill();
    }

    stdout.writeln(line);
  });

  await process.exitCode; // wait until the process is done
  await outputSubscription.cancel();
  exit(isSuccessful ? 0 : 1);
}
