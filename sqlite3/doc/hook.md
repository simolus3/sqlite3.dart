Most operating systems make copies of SQLite as a native library available to applications.
However, these libraries are inconsistent in their compile-time options (resulting in different
SQLite features being available on different platforms) and are often outdated.

To avoid this inconsistency, `package:sqlite3/` bundles a copy of SQLite with your application
by default, and it will prefer to use that copy over the one from the operating system.
To do that, it uses a new Dart and Flutter feature called [hooks](https://dart.dev/tools/hooks).
More information on hooks is available under that link, this page describes options relevant to
`package:sqlite3`.

## Default binaries

Each [GitHub release](https://github.com/simolus3/sqlite3.dart/releases) of the SQLite package
contains pre-compiled SQLite versions as shared libraries for all platforms supported by Dart.
These binaries are compiled directly from upstream sources in GitHub actions, and the version of
`package:sqlite3` published to pub.dev contains sha256 references that are compared against
downloaded files.

These binaries use the following compile-time options:

```
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
```

For each platform, two sets of binaries are available:

- [Upstream SQLite](https://sqlite.org/download.html).
- The [SQLite3MultipleCiphers build](https://github.com/utelle/SQLite3MultipleCiphers/releases)
  providing encryption support.

SQLite is used by default, but SQLite3MultipleCiphers can be selected through user defines, e.g.
by adding this to `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc # for SQLite3MultipleCiphers, default is sqlite3
```

## System-provided SQLite

Depending on how you distribute your app, you may want to use the SQLite version shipped with
the operating system.

To do so, use the following user defines:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system # or "process", or "excutable"
```

These options behave as follows:

1. "system" instructs the Dart embedder to lookup SQLite from the operating system, e.g. with a
   `dlopen("libsqlite3.so")` on Linux.
2. "process" looks for SQLite symbols in the current [process](https://api.dart.dev/dart-ffi/DynamicLibrary/DynamicLibrary.process.html), which can be useful when your executable already depends on
  SQLite (instead of explicitly requesting it with `dlopen`).
3. "executable" looks for SQLite symbols in the current [executable](https://api.dart.dev/dart-ffi/DynamicLibrary/DynamicLibrary.executable.html), which is useful when linking SQLite statically.

## Custom SQLite builds

If you want to customize the SQLite build to use with `package:sqlite3`, you can
also use user defines for that.

First, download the `sqlite3.c` file you want to use into your workspace. Then,
add this section to your pubspec:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: source
      path: path/to/sqlite3.c # relative to your workspace root
      defines: # optional
        default_options: false # optional, to disable default compile-time options used by package:sqlite3
        defines:
          - SQLITE_THREADSAFE=1
          - SQLITE_LIKE_DOESNT_MATCH_BLOBS
```

### Alternatives

Using the `source` mode to compile SQLite from sources in build hook can't
cover all customization needs you may have. When building SQLCipher for
instance, you may want to pass custom linker options to the build process.

There is no good way to support arbitrary customization in build hooks today.
However, `package:sqlite3` will work with all SQLite builds that are ABI-compatible
with standard SQLite (it also runs checks at runtime before using methods that
are not commonly enabled on all builds).
If you control the build process of your application, you can use an external
build system (like SwiftPM or CMake) to statically link SQLite into your application.
Then, use `source: executable` to make `package:sqlite3` use that copy instead
of building its own.
