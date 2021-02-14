import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  // Regular test driver isn't working, so this is what we do.

  final process = await Process.start(
      'flutter', ['run', '--target=test_driver/integration.dart']);

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
