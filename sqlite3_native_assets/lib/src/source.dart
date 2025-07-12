import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'user_defines.dart';

/// Describes how to obtain a source for SQLite.
sealed class SqliteSource {
  static SqliteSource parse(UserDefinesOptions options) {
    return switch (options.readObject('source')) {
      {'amalgamation': final source} => DownloadAmalgamation._parse(source!),
      {'local': final local} => ExistingAmalgamation(
        options.inputPath(local as String),
      ),
      {'system': _} => const UseFromSystem(),
      {'process': _} => const UseFromProcess(),
      {'executable': _} => const UseFromExecutable(),
      false => const DontLinkSqlite(),
      _ => const DownloadAmalgamation(),
    };
  }
}

/// Obtain a copy of SQLite by downloading the amalgamation.
final class DownloadAmalgamation implements SqliteSource {
  /// The URL to download SQLite from.
  final String uri;

  /// The name of the single C file to compile from the downloaded archive.
  final String filename;

  const DownloadAmalgamation({
    this.uri = 'https://sqlite.org/2025/sqlite-amalgamation-3500200.zip',
    this.filename = 'sqlite3.c',
  });

  factory DownloadAmalgamation._parse(Object definition) {
    if (definition is String) {
      return DownloadAmalgamation(uri: definition);
    } else if (definition is Map) {
      return DownloadAmalgamation(
        uri: definition['uri'] as String,
        filename: (definition['filename'] as String?) ?? 'sqlite3.c',
      );
    } else {
      throw ArgumentError.value(
        definition,
        'definition',
        'Unknown amalgamation description',
      );
    }
  }
}

/// Compile SQLite from an existing `sqlite3.c` file.
final class ExistingAmalgamation implements SqliteSource {
  /// Path to the `sqlite3.c` source file to compile.
  final String sqliteSource;

  const ExistingAmalgamation(this.sqliteSource);
}

/// Marker type for [SqliteSource]s that don't require us to compile SQLite.
sealed class DontCompileSqlite implements SqliteSource {
  LinkMode? resolveLinkMode(BuildInput input);
}

/// Link SQLite from the system instead of compiling it manually.
final class UseFromSystem implements SqliteSource, DontCompileSqlite {
  const UseFromSystem();

  @override
  LinkMode? resolveLinkMode(BuildInput input) => DynamicLoadingSystem(
    Uri.parse(switch (input.config.code.targetOS) {
      OS.windows => 'sqlite3.dll',
      OS.macOS || OS.iOS => 'libsqlite3.dylib',
      _ => 'libsqlite3.so',
    }),
  );
}

/// Look up SQLite in process without compiling it.
final class UseFromProcess implements SqliteSource, DontCompileSqlite {
  const UseFromProcess();

  @override
  LinkMode? resolveLinkMode(BuildInput input) => LookupInProcess();
}

/// Look up SQLite in built executable without compiling it.
final class UseFromExecutable implements SqliteSource, DontCompileSqlite {
  const UseFromExecutable();

  @override
  LinkMode? resolveLinkMode(BuildInput input) => LookupInExecutable();
}

/// Don't compile or link SQLite at all.
///
/// This is meant as an escape hatch for when users want to use
/// `sqlite3_native_assets` with their own build script.
final class DontLinkSqlite implements SqliteSource, DontCompileSqlite {
  const DontLinkSqlite();

  @override
  LinkMode? resolveLinkMode(BuildInput input) => null;
}
