import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

import 'assets.dart';
import 'asset_hashes.dart';
import 'utils.dart';

/// Possible sources to obtain a `libsqlite3.so` (or the equivalent for other
/// platforms).
sealed class SqliteBinary {
  static SqliteBinary forBuild(BuildInput input) {
    final userDefines = input.userDefines;
    switch (userDefines['source']) {
      case null:
      case 'sqlite3':
        return PrecompiledFromGithubAssets(LibraryType.sqlite3);
      case 'sqlite3mc':
        return PrecompiledFromGithubAssets(LibraryType.sqlite3mc);
      case 'test-sqlite3':
        return PrecompiledForTesting(LibraryType.sqlite3);
      case 'test-sqlite3mc':
        return PrecompiledForTesting(LibraryType.sqlite3mc);
      case 'system':
        final osSpecificNameKey = 'name_${input.config.code.targetOS.name}';

        return LookupSystem(
          ((userDefines[osSpecificNameKey] ?? userDefines['name'] ?? 'sqlite3')
              as String),
        );
      case 'process':
        return SimpleBinary.fromProcess;
      case 'executable':
        return SimpleBinary.fromExecutable;
      case 'source':
        return CompileSqlite(
          sourceFile: userDefines.path('path')!.toFilePath(),
          defines: CompilerDefines.parse(
            userDefines,
            input.config.code.targetOS,
          ),
        );
      default:
        throw ArgumentError.value(
          userDefines['source'],
          'source',
          'Unknown source. Must be sqlite3, sqlite3mc, system, process or '
              'executable',
        );
    }
  }
}

/// A [SqliteBinary] not built or downloaded by the hook.
sealed class ExternalSqliteBinary implements SqliteBinary {
  LinkMode resolveLinkMode(BuildInput input);
}

/// Load a `sqlite3` library via `dlopen('libsqlite3.so')` or another platform-
/// specific name,
final class LookupSystem implements ExternalSqliteBinary {
  /// The base name, used to construct an OS-specific library name.
  final String name;

  const LookupSystem(this.name);

  @override
  LinkMode resolveLinkMode(BuildInput input) {
    final targetOS = input.config.code.targetOS;

    return DynamicLoadingSystem(
      Uri.parse(targetOS.libraryFileName(name, DynamicLoadingBundled())),
    );
  }
}

/// Options for resolving a sqlite binary that don't require nested options.
enum SimpleBinary implements ExternalSqliteBinary {
  /// Lookup a `sqlite3` library that has already been loaded into the process.
  fromProcess,

  /// Lookup `sqlite3` symbols in the current executable.
  fromExecutable;

  @override
  LinkMode resolveLinkMode(BuildInput input) {
    switch (this) {
      case SimpleBinary.fromProcess:
        return LookupInProcess();
      case SimpleBinary.fromExecutable:
        return LookupInExecutable();
    }
  }
}

sealed class PrecompiledBinary implements SqliteBinary {
  final LibraryType type;

  const PrecompiledBinary._(this.type);

  PrebuiltSqliteLibrary resolveLibrary(CodeConfig config) {
    return PrebuiltSqliteLibrary.resolve(config, type);
  }

  Stream<Uint8List> _fetchFromSource(
    BuildInput input,
    BuildOutputBuilder output,
    String filename,
  );

  Stream<Uint8List> fetch(
    BuildInput input,
    BuildOutputBuilder output,
    PrebuiltSqliteLibrary library,
  ) {
    return Stream.multi((listener) {
      final (filename, hash) = _filenameAndHash(library);
      final source = _fetchFromSource(input, output, filename);

      final digestSink = OnceSink<Digest>();
      final hasher = sha256.startChunkedConversion(digestSink);

      source.listen(
        (data) {
          listener.addSync(data);
          hasher.add(data);
        },
        onError: listener.addErrorSync,
        onDone: () {
          hasher.close();
          final digest = digestSink.value!;

          if (digest.toString() != hash) {
            listener.addError(
              StateError(
                'Hash of downloaded file $filename is $digest, expected $hash.',
              ),
            );
          }

          listener.close();
        },
      );
    });
  }

  (String, String) _filenameAndHash(PrebuiltSqliteLibrary library) {
    final filename = library.filename;
    final expectedHash = assetNameToSha256Hash[filename];
    if (expectedHash == null) {
      throw UnsupportedError(
        'No known file hash for $filename. '
        'Please file an issue on https://github.com/simolus3/sqlite3.dart with '
        'the version of the sqlite3 package in use.',
      );
    }

    return (filename, expectedHash);
  }
}

/// Download pre-compiled binaries from the GH release for the `sqlite3`
/// package.
final class PrecompiledFromGithubAssets extends PrecompiledBinary {
  const PrecompiledFromGithubAssets(super.type) : super._();

  @override
  Stream<Uint8List> _fetchFromSource(
    BuildInput input,
    BuildOutputBuilder output,
    String filename,
  ) async* {
    final client = HttpClient()
      // From Dart 3.11, proxy-related environment variables are passed to
      // hooks. We respect them to ensure we can download these binaries in
      // environments where that's required
      // https://github.com/simolus3/sqlite3.dart/issues/335
      ..findProxy = HttpClient.findProxyFromEnvironment;
    final request = await client.getUrl(
      Uri.https(
        'github.com',
        'simolus3/sqlite3.dart/releases/download/${releaseTag!}/$filename',
      ),
    );
    final response = await request.close();

    await for (final chunk in response) {
      if (chunk is Uint8List) {
        yield chunk;
      } else {
        yield Uint8List.fromList(chunk);
      }
    }

    client.close();
  }
}

/// A variant of [PrecompiledFromGithubAssets] that doesn't require a github
/// release.
///
/// This is only used to test the package: We download the assets we would
/// upload for a release build into a folder, and then have the hook look them
/// up there.
final class PrecompiledForTesting extends PrecompiledBinary {
  const PrecompiledForTesting(super.type) : super._();

  @override
  Stream<Uint8List> _fetchFromSource(
    BuildInput input,
    BuildOutputBuilder output,
    String filename,
  ) {
    final uri = input.userDefines.path('directory')!.resolve(filename);
    output.dependencies.add(uri);

    return File(uri.toFilePath()).openRead().map(
      (event) => switch (event) {
        final Uint8List bytes => bytes,
        _ => Uint8List.fromList(event),
      },
    );
  }
}

final class CompileSqlite implements SqliteBinary {
  /// Path to the `sqlite3.c` source file to compile.
  final String sourceFile;

  /// User-defines for the SQLite compilation.
  final CompilerDefines defines;

  CompileSqlite({required this.sourceFile, required this.defines});
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
