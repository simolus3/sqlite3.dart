import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart';

import 'defines.dart';
import 'source.dart';
import 'user_defines.dart';

final class SqliteBuild {
  final SqliteSource source;
  final CompilerDefines defines;
  final BuildInput input;
  final BuildOutputBuilder output;

  bool trackSourcesAsDependencyForCompilation = true;

  SqliteBuild(this.input, this.output)
    : source = SqliteSource.parse(UserDefinesOptions.fromHooks(input)),
      defines = CompilerDefines.parse(UserDefinesOptions.fromHooks(input));

  Future<String?> _prepareBuild() async {
    switch (source) {
      case DownloadAmalgamation(:final uri, :final filename):
        // Don't track the source because we're the ones creating the local
        // copy.
        final response = await get(Uri.parse(uri));
        if (response.statusCode != 200) {
          throw 'Could not download sqlite3: ${response.statusCode} ${response.reasonPhrase} ${response.body}';
        }
        final archive = ZipDecoder().decodeBytes(response.bodyBytes);
        final filepath =
            input.outputDirectory.resolve('sqlite3.c').toFilePath();
        for (final file in archive) {
          if (posix.basename(file.name) == filename) {
            await File(filepath).writeAsBytes(file.content);
          }
        }
        trackSourcesAsDependencyForCompilation = false;
        return filepath;
      case ExistingAmalgamation(:final sqliteSource):
        return sqliteSource;
      case UseFromSystem():
      case UseFromExecutable():
      case UseFromProcess():
      case DontLinkSqlite():
        return null;
    }
  }

  Future<void> _compile(String source) async {
    final builder = CBuilder.library(
      name: 'sqlite3',
      assetName: 'sqlite3_native_assets.dart',
      sources: [source],
      defines: defines,
    );

    if (trackSourcesAsDependencyForCompilation) {
      // We can just run a regular build.
      await builder.run(
        input: input,
        output: output,
        logger:
            Logger('')
              ..level = Level.ALL
              ..onRecord.listen((record) => print(record.message)),
      );
    } else {
      final temporaryOutputs = BuildOutputBuilder();
      await builder.run(
        input: input,
        output: temporaryOutputs,
        logger:
            Logger('')
              ..level = Level.ALL
              ..onRecord.listen((record) => print(record.message)),
      );

      // Forward generated assets but ignore dependencies
      for (final rawAsset in temporaryOutputs.json['assets'] as List) {
        output.assets.addEncodedAsset(EncodedAsset.fromJson(rawAsset));
      }
    }
  }

  Future<void> runBuild() async {
    final resolvedSourceFile = await _prepareBuild();

    if (resolvedSourceFile != null) {
      await _compile(resolvedSourceFile);
    } else if (source case final DontCompileSqlite dontCompile) {
      if (dontCompile.resolveLinkMode(input) case final linkMode?) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: 'sqlite3_native_assets.dart',
            linkMode: linkMode,
          ),
        );
      }
    }
  }
}
