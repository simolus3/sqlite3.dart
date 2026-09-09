import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

// We currently support glibc 2.34.0 as a minimum version.
final _maxVersionExclusive = Version.parse('2.35.0');

/// Verifies that a set of files don't use versioned glibc symbols from versions
/// we don't support.
///
/// Usage: dart tool/check_glibc_version.dart <files>.
void main(List<String> args) async {
  final brokenSymbols = (await args.map(checkLibrary).wait).flattenedToList;

  brokenSymbols.forEach(print);
  if (brokenSymbols.isNotEmpty) {
    exit(1);
  }

  print('No broken symbols found in ${args.join(', ')}');
}

final _versionSuffix = RegExp(r'@GLIBC_(.+)');

final class OffendingSymbol(final String file, final String name) {
  @override
  String toString() {
    return '$name in $file';
  }
}

Future<List<OffendingSymbol>> checkLibrary(String file) async {
  const executable = 'nm';
  final args = ['-Du', '--format=just-symbols', file];
  final process = await Process.start(executable, args);
  final brokenSymbols = <OffendingSymbol>[];

  await for (final symbol
      in process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (_symbolVersion(symbol) case final version?
        when version >= _maxVersionExclusive) {
      brokenSymbols.add(OffendingSymbol(file, symbol));
    }
  }

  if (await process.exitCode case final code when code != 0) {
    throw ProcessException(executable, args);
  }
  return brokenSymbols;
}

Version? _symbolVersion(String symbol) {
  if (_versionSuffix.firstMatch(symbol) case final versioned?) {
    return switch (versioned.group(1)!.split('.')) {
      [final major, final minor] => Version(.parse(major), .parse(minor), 0),
      [final major, final minor, final patch] => Version(
        .parse(major),
        .parse(minor),
        .parse(patch),
      ),
      _ => throw UnsupportedError('Unknown version suffix $symbol'),
    };
  }

  return null;
}
