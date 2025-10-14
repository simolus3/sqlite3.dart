import 'dart:convert';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Possible sources to obtain a `libsqlite3.so` (or the equivalent for other
/// platforms).
sealed class SqliteBinary {
  static SqliteBinary forBuild(BuildInput input) {
    // TODO: Parse user defines
    return SimpleBinary.fromSystem;
  }
}

/// Options for resolving a sqlite binary that don't require nested options.
enum SimpleBinary implements SqliteBinary {
  /// Use the `sqlite3` shipping with the operating system.
  fromSystem,

  /// Lookup a `sqlite3` library that has already been loaded into the process.
  fromProcess,

  /// Lookup `sqlite3` symbols in the current executable.
  fromExecutable;

  LinkMode resolveLinkMode(BuildInput input) {
    switch (this) {
      case SimpleBinary.fromSystem:
        final targetOS = input.config.code.targetOS;

        return DynamicLoadingSystem(Uri.parse(switch (targetOS) {
          OS.windows => 'sqlite3.dll',
          OS.macOS || OS.iOS => 'libsqlite3.dylib',
          OS.linux => 'libsqlite3.so',
          _ => throw ArgumentError.value(targetOS, 'targetOS',
              'Does not have sqlite3 in its system libraries'),
        }));
      case SimpleBinary.fromProcess:
        return LookupInProcess();
      case SimpleBinary.fromExecutable:
        return LookupInExecutable();
    }
  }
}

/// Download pre-compiled binaries from the GH release for the `sqlite3`
/// package.
final class PrecompiledFromGithubAssets implements SqliteBinary {
  final String releaseTag;

  PrecompiledFromGithubAssets(this.releaseTag);
}

/// A variant of [PrecompiledFromGithubAssets] that doesn't require a github
/// release.
///
/// This is only used to test the package: We download the assets we would
/// upload for a release build into a folder, and then have the hook look them
/// up there.
final class PrecompiledForTesting implements SqliteBinary {
  PrecompiledForTesting();
}

final class CompileSqlite implements SqliteBinary {
  /// How to obtain the `sqlite3.c` source to compile.
  final SqliteSources sources;

  /// User-defines for the SQLite compilation.
  final CompilerDefines defines;

  CompileSqlite({required this.sources, required this.defines});
}

/// If we're compiling SQLite from source, a way to obtain these sources.
sealed class SqliteSources {}

/// Obtain a copy of SQLite by downloading the amalgamation.
final class DownloadAmalgamation implements SqliteSources {
  /// The URL to download SQLite from.
  final String uri;

  /// The name of the single C file to compile from the downloaded archive.
  final String filename;

  const DownloadAmalgamation({
    this.uri = 'https://sqlite.org/2025/sqlite-amalgamation-3500200.zip',
    this.filename = 'sqlite3.c',
  });

  // ignore: unused_element
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

/// Compile SQLite from an existing `sqlite3.c` file that has been vendored into
/// the project.
final class ExistingAmalgamation implements SqliteSources {
  /// Path to the `sqlite3.c` source file to compile.
  final String sqliteSource;

  const ExistingAmalgamation(this.sqliteSource);
}

/// Definition options to use when compiling SQLite.
extension type const CompilerDefines(Map<String, String?> flags)
    implements Map<String, String?> {
  CompilerDefines overrideWith(CompilerDefines other) {
    return CompilerDefines({...flags, ...other.flags});
  }

  static CompilerDefines parse(HookInputUserDefines defines, OS targetOS) {
    final obj = defines['defines'];

    // Include default options when not explicitly disabled.
    final includeDefaults = switch (obj) {
      {'default_options': false} => false,
      _ => true,
    };

    // Allow adding additional options under defines key or as a top-level
    // array.
    final additionalDefines = switch (obj) {
      {'defines': final options} => _parseOption(options),
      final List<Object?> list => _parseOption(list),
      _ => null,
    };

    final start = includeDefaults
        ? CompilerDefines.defaults(targetOS == OS.windows)
        : const CompilerDefines({});

    return switch (additionalDefines) {
      final added? => start.overrideWith(added),
      null => start,
    };
  }

  static CompilerDefines _parseOption(Object? option) {
    if (option is List) {
      return _parseLines(option.cast());
    } else if (option is Map) {
      return CompilerDefines(option.cast());
    } else {
      throw ArgumentError.value(
        option,
        'option',
        'Could not extract defines, should be an array or map of options',
      );
    }
  }

  static CompilerDefines _parseLines(Iterable<String> lines) {
    final entries = <String, String?>{};
    for (final line in lines) {
      if (line.contains('=')) {
        final [key, value] = line.trim().split('=');
        entries[key] = value;
      } else {
        entries[line.trim()] = null;
      }
    }

    return CompilerDefines(entries);
  }

  static CompilerDefines defaults(bool windows) {
    final defines = _parseLines(const LineSplitter().convert(_defaultDefines));
    if (windows) {
      defines['SQLITE_API'] = '__declspec(dllexport)';
    }
    return defines;
  }
}

// Keep in sync with tool/compile_sqlite.dart
const _defaultDefines = '''
  SQLITE_ENABLE_DBSTAT_VTAB
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_RTREE
  SQLITE_ENABLE_MATH_FUNCTIONS
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
  SQLITE_ENABLE_SESSION
  SQLITE_ENABLE_PREUPDATE_HOOK
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_HAVE_LOCALTIME_R
  SQLITE_HAVE_LOCALTIME_S
  SQLITE_HAVE_MALLOC_USABLE_SIZE
  SQLITE_HAVE_STRCHRNUL
''';
