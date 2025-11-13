## Upgrading `package:sqlite3`.

This document collects notes on upgrading the `sqlite3` package from version
2.x to version 3.x.

For almost all users, upgrading should be very simple:

1. If you depend on `sqlite3_flutter_libs`, stop doing that.
2. If you depend on `sqlcipher_flutter_libs`, stop doing that and read
   [encryption](#encryption).
3. Upgrade to `sqlite3: ^3.0.0`.
4. Make sure you update your `sqlite3.wasm` by downloading it from the
   [latest releases](https://github.com/simolus3/sqlite3.dart/releases).
5. If you had `open.overrideFor` code to customize how SQLite is loaded, that needs
   to be removed. The package exclusively uses hooks now.

Version 3.x relies on [hooks](https://dart.dev/tools/hooks) to automatically bundle
a pre-compiled version of SQLite with your application. By default, these binaries
are downloaded from the GitHub releases of this package.
This mechanism replaces the earlier scheme based on platform-specific build
scripts.

If you want to compile SQLite yourself instead of relying on those downloaded
binaries, see [custom SQLite builds](#custom-sqlite-builds).

Also note that the build definition for `sqlite3.wasm` has changed. New sources
are available in [sqlite3_wasm_build](./sqlite3_wasm_build/).

## Encryption

If you've been using SQLCipher to use encrypted databases, note that SQLCipher is
no longer available with version 3. However, a precompiled version of SQLite3MultipleCiphers
can easily be enabled by adding this to your pubspec:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

SQLite3MultipleCiphers should be compatible with existing databases created by SQLCipher when running the following statements from SQLite3MultipleCiphers:

```
pragma cipher = 'sqlcipher';
pragma legacy = 4;

pragma key = '...your key...';
```

For details, see [hook options](./sqlite3/doc/hook.md).

## Custom SQLite builds

If you want to customize the SQLite build for `package:sqlite3`, there are two options:

1. Downloading `sqlite3.c` into your project and then following the "Custom SQLite builds"
   section of [hook options](./sqlite3/doc/hook.md).
2. Using external build scripts (such as SwiftPM or CMake) to statically link SQLite into your
   Flutter application, and then following the "Alternatives" section of [hook options](./sqlite3/doc/hook.md).

For details, see [hook options](./sqlite3/doc/hook.md).

If these customization options don't meet your needs, please open an issue!
