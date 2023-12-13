import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:cli_config/cli_config.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  final config = await BuildConfig.fromArgs(args);
  final script = SqliteBuildScript(config: config);
  await script.build();
}

enum SqliteSource {
  /// Download an amagalmation zip file.
  url,

  /// Create an empty `libdart_sqlite3.so` that depends on `libsqlite3.so`,
  /// effectively using the system's sqlite3 when loaded.
  system,

  /// Use the sqlite3 amalgation that is shipping with the `sqlite3` package.
  vendored;

  static const defaultSource = vendored;

  static SqliteSource fromConfig(Config config) {
    final value = config.optionalString('sqlite3.source', validValues: [
      for (final option in values) option.name,
    ]);

    if (value == null) {
      return defaultSource;
    } else {
      return values.byName(value);
    }
  }
}

class SqliteBuildOptions {
  final SqliteSource source;
  final Uri? downloadUrl;

  SqliteBuildOptions({required this.source, required this.downloadUrl});

  factory SqliteBuildOptions.fromConfig(Config config) {
    final source = SqliteSource.fromConfig(config);
    Uri? downloadUrl;

    if (source == SqliteSource.url) {
      downloadUrl = Uri.parse(config.string('sqlite3.url'));
    }

    return SqliteBuildOptions(
      source: source,
      downloadUrl: downloadUrl,
    );
  }
}

class SqliteBuildScript {
  final BuildConfig config;
  final SqliteBuildOptions options;

  final Logger logger = Logger('build.sqlite3');
  final BuildOutput output = BuildOutput();

  final Directory outDir;

  SqliteBuildScript({required this.config})
      : options = SqliteBuildOptions.fromConfig(config.config),
        outDir = Directory.fromUri(config.outDir) {
    logger.onRecord.listen(print);
  }

  Future<void> build() async {
    await outDir.create(recursive: true);

    final builder = await _compileSqlite();

    await builder.run(
      buildConfig: config,
      buildOutput: output,
      logger: logger,
    );

    await output.writeToFile(outDir: config.outDir);
  }

  Stream<List<int>> _extractVendoredSqlite() {
    final source = config.packageRoot.resolve('assets/sqlite3.c.gz');
    output.dependencies.dependencies.add(source);

    return File(source.toFilePath()).openRead().transform(gzip.decoder);
  }

  Stream<List<int>> _downloadSqlite() {
    throw UnimplementedError();
  }

  Stream<List<int>> _emptySourceForSystem() async* {
    yield utf8.encode('#include <sqlite3.h>\n');
  }

  Future<CBuilder> _compileSqlite() async {
    final sourceCode = switch (options.source) {
      SqliteSource.vendored => _extractVendoredSqlite(),
      SqliteSource.url => _downloadSqlite(),
      SqliteSource.system => _emptySourceForSystem(),
    };

    // Extract source code into an intermediate file
    final sqlite3DotC = config.outDir.resolve('sqlite3.c');
    late final writingToSqlite3DotC =
        File(sqlite3DotC.toFilePath()).openWrite();
    await writingToSqlite3DotC.addStream(sourceCode);

    // Also add helper functions we need to work around current limitations in
    // Dart's FFI system.
    await File(config.packageRoot
            .resolve('assets/dart_workarounds.c')
            .toFilePath())
        .openRead()
        .pipe(writingToSqlite3DotC);
    await writingToSqlite3DotC.done;

    return CBuilder.library(
      name: 'dart_sqlite3',
      assetId: 'package:sqlite3/src/ffi/sqlite3.g.dart',
      sources: [
        // CBuilder resolves sources relative to config.packageRoot.path, so
        // convert the intermediate source to that relative path.
        p
            .toUri(
              p.relative(sqlite3DotC.path, from: config.packageRoot.path),
            )
            .toString(),
      ],
      defines: {
        // Disable deprecated features
        'SQLITE_DQS': '0',
        'SQLITE_OMIT_DEPRECATED': null,

        // Recommended options
        'SQLITE_MAX_EXPR_DEPTH': '0',
        'SQLITE_TEMP_STORE': '2',
        'SQLITE_DEFAULT_MEMSTATUS': '0',

        // Additional features we want
        'SQLITE_ENABLE_FTS5': null,
        'SQLITE_ENABLE_RTREE': null,

        // Omit things we don't use
        'SQLITE_OMIT_TRACE': null,
        'SQLITE_OMIT_TCL_VARIABLE': null,
//      'SQLITE_OMIT_SHARED_CACHE': null,
        'SQLITE_OMIT_PROGRESS_CALLBACK': null,
        'SQLITE_LOAD_EXTENSION': null,
        'SQLITE_OMIT_GET_TABLE': null,
        'SQLITE_OMIT_DECLTYPE': null,
        'SQLITE_OMIT_AUTHORIZATION': null,

        if (config.targetOs == OS.linux || config.targetOs == OS.android) ...{
          'SQLITE_USE_ALLOCA': null,
          'SQLITE_HAVE_ISNAN': null,
          'SQLITE_HAVE_LOCALTIME_R': null,
          'SQLITE_HAVE_LOCALTIME_S': null,
          'SQLITE_HAVE_MALLOC_USABLE_SIZE': null,
          'SQLITE_HAVE_STRCHRNUL': null,
        },

        if (config.targetOs == OS.windows)
          // Actually export functions meant to be exported.
          'SQLITE_API': '__declspec(dllexport)',
        if (config.buildMode == BuildMode.debug) ...{
          // Enable SQLite internal checks.
          'SQLITE_DEBUG': null,
          'SQLITE_MEMDEBUG': null,
          // Enable SQLite API usage checks.
          'SQLITE_ENABLE_API_ARMOR': null
        } else
          // Don't include any testing hooks
          'SQLITE_UNTESTABLE': null,
      },
      flags: _buildFlags,
    );
  }

  List<String> get _buildFlags {
    return [
      if (config.buildMode == BuildMode.release)
        if (config.targetOs == OS.windows) '/02' else '-O3',

      // todo: Make this work on all platforms
      if (options.source == SqliteSource.system) '-lsqlite3',
    ];
  }
}
