import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final source = input.outputDirectory.resolve('sqlite3.c');
    final response = await get(
      Uri.parse('https://sqlite.org/2025/sqlite-amalgamation-3490000.zip'),
    );
    if (response.statusCode != 200) {
      throw 'Could not download sqlite3: ${response.statusCode} ${response.reasonPhrase} ${response.body}';
    }
    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    for (final file in archive) {
      if (posix.basename(file.name) == 'sqlite3.c') {
        await File(source.toFilePath()).writeAsBytes(file.content);
      }
    }

    final builder = CBuilder.library(
      name: 'sqlite3',
      assetName: 'sqlite3_native_assets.dart',
      sources: [source.toFilePath()],
    );

    await builder.run(
      input: input,
      // This adds a dependency on sqlite3.c, which confuses dependency tracking
      // because that file was also changed by this build script.
      output: _IgnoreSourceDependency(output),
      logger:
          Logger('')
            ..level = Level.ALL
            ..onRecord.listen((record) => print(record.message)),
    );
  });
}

final class _IgnoreSourceDependency extends BuildOutputBuilder {
  final BuildOutputBuilder _inner;

  _IgnoreSourceDependency(this._inner);

  @override
  EncodedAssetBuildOutputBuilder get assets => _inner.assets;

  @override
  void addDependencies(Iterable<Uri> uris) {
    super.addDependencies(uris.where((e) => url.extension(e.path) != '.c'));
  }
}
