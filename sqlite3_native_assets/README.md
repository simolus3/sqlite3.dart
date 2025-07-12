__Like native assets, this package is experimental.__

This package provides SQLite as a [native code asset](https://dart.dev/interop/c-interop#native-assets).

It has the same functionality as the `sqlite3_flutter_libs` package,
except that it also works without Flutter.

## Getting started

Add this package to your dependencies: `dart pub add sqlite3_native_assets`.
That's it! No build scripts to worry about, it works out of the box.

## Usage

You can keep using all your existing code using `package:sqlite3`.
The only difference is how you access it.
For now, you'll have to replace the top-level `sqlite3` getter
with `sqlite3Native`.

```dart
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_native_assets/sqlite3_native_assets.dart';

void main() {
  final Sqlite3 sqlite3 = sqlite3Native;
  print('Using sqlite3 ${sqlite3.version}');
}
```

## Options

This package supports [user-defines](https://github.com/dart-lang/native/pull/2165)
to customize how SQLite is built.
You can configure this with an entry in your pubspec:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      # Your options here
```

> [!NOTE]
> As of 2025-04-10, support for user-defines in native assets is a _very_ recent feature
> that's still being rolled out to Flutter and Dart SDKs.

### Configuring SQLite sources

By default, `sqlite3_native_assets` will download and compile SQLite. It's possible to customize:

__The download URL__

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        amalgamation: https://sqlite.org/2025/sqlite-amalgamation-3490100.zip
```

You can also change the name of the main library file:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        amalgamation:
          uri: https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.2.1/sqlite3mc-2.2.1-sqlite-3.50.2-amalgamation.zip
          filename: sqlite3mc_amalgamation.c
```

__Using a local `sqlite3.c`__

If you already have a `sqlite3.c` file in your project that you want to use instead of downloading
SQLite, you can use the `local` option:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        local: third_party/sqlite3/sqlite3.c
```

__Load dynamically__

You can also instruct this package to attempt to load SQLite from the operating system (if it's in `$PATH`)
or by looking up symbols in the executable / the running process:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      source:
        system: # can also use process: or executable: here
```

__Skip build__

You can also instruct `sqlite3_native_assets` to not build, link or configure SQLite in any way.
This is useful as an escape hatch if you have a custom SQLite build that you would like to apply
instead:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      source: false
```

In this case, you can write your own build hooks. When compiling SQLite to a library, add a derived
`CodeAssets` to your outputs like this:

```dart
CodeAsset(
  package: 'sqlite3_native_assets',
  name: 'sqlite3_native_assets.dart',
  linkMode: linkMode,
  os: input.config.code.targetOS,
  architecture: input.config.code.targetArchitecture,
)
```

If the `package` and `name` match, the custom library will get used.

### Configuring compile-time options

You can override the [compile-time options](https://sqlite.org/compile.html) this
package uses to compile SQLite.
By default, a reasonable set of compile-time options including the recommended options and
some others to enable useful features and performance enhancements are enabled.

You can add additional entries to this list, either as a map:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      defines:
        defines:
          SQLITE_LIKE_DOESNT_MATCH_BLOBS:
          SQLITE_MAX_SCHEMA_RETRY: 2
```

or as a list:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      defines:
        defines:
          - SQLITE_LIKE_DOESNT_MATCH_BLOBS
          - SQLITE_MAX_SCHEMA_RETRY=2
```

You can also disable the default compile-time options:

```yaml
hooks:
  user_defines:
    sqlite3_native_assets:
      defines:
        default_options: false
        defines:
          # Your preferred options here
```
