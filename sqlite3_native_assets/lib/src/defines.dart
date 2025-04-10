// Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
import 'dart:convert';

import 'user_defines.dart';

/// Definition options to use when compiling SQLite.
extension type const CompilerDefines(Map<String, String?> flags)
    implements Map<String, String?> {
  CompilerDefines overrideWith(CompilerDefines other) {
    return CompilerDefines({...flags, ...other.flags});
  }

  static CompilerDefines parse(UserDefinesOptions defines) {
    final obj = defines.readObject('defines');

    // Include default options when not explicitly disabled.
    final includeDefaults = switch (obj) {
      {'default_options': false} => false,
      _ => true,
    };

    // Allow adding additional options under defines key or as a top-level
    // array.
    final additionalDefines = switch (obj) {
      {'defines': final options} => _parseOption(options),
      final List list => _parseOption(list),
      _ => null,
    };

    final start =
        includeDefaults
            ? CompilerDefines.defaults()
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

  static CompilerDefines defaults() {
    return _parseLines(const LineSplitter().convert(_defaultDefines));
  }
}

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
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_HAVE_LOCALTIME_R
  SQLITE_HAVE_LOCALTIME_S
  SQLITE_HAVE_MALLOC_USABLE_SIZE
  SQLITE_HAVE_STRCHRNUL
''';
