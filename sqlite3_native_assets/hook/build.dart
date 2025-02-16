import 'dart:convert';
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
      defines: collectDefines(),
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

// Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
const _defines = '''
  SQLITE_ENABLE_DBSTAT_VTAB
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_RTREE
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
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_HAVE_LOCALTIME_R
  SQLITE_HAVE_LOCALTIME_S
  SQLITE_HAVE_MALLOC_USABLE_SIZE
  SQLITE_HAVE_STRCHRNUL
''';

Map<String, String?> collectDefines() {
  final entries = <String, String?>{};
  for (final line in const LineSplitter().convert(_defines)) {
    if (line.contains('=')) {
      final [key, value] = line.trim().split('=');
      entries[key] = value;
    } else {
      entries[line.trim()] = null;
    }
  }
  return entries;
}
