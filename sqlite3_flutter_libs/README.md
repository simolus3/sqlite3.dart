# sqlite3_flutter_libs

This package intentionally contains no Dart code. Flutter apps depending on this package will
contain native `sqlite3` libraries on Android, iOS and macOS.

For more details on how to actually use this package in a Flutter app, see 
[sqlite3](https://pub.dev/packages/sqlite3).

## Notes on Android

### Included platforms

Note that, on Android, this library will bundle sqlite3 for all of the following platforms:

- `arm64-v8a`
- `armeabi-v7a`
- `x86`
- `x86_64`

If you don't intend to release to 32-bit `x86` devices, you'll need to apply a 
[filter](https://developer.android.com/ndk/guides/abis#gc) in your `build.gradle`:

```gradle
android {
    defaultConfig {
        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86_64'
        }
    }
}
```

### Problems on Android 6

There appears to be a problem when loading native libraries on Android 6 (see [this issue](https://github.com/simolus3/moor/issues/895#issuecomment-720195005)).
If you're seeing those crashes, you could try setting `android.bundle.enableUncompressedNativeLibs=false` in your `gradle.properties`
file. Be aware that this increases the size of your application when installed.

Alternatively, you can use the `applyWorkaroundToOpenSqlite3OnOldAndroidVersions` method from this library.
It will try to open `sqlite3` in Java, which seems to work more reliably. After sqlite3 has been loaded from Java,
we can open it in Dart too.
The method should be called before using `sqlite3` (either directly or indirectly through say a `NativeDatabase` from `package:drift`).

As `applyWorkaroundToOpenSqlite3OnOldAndroidVersions` uses platform channels, there may be issues when using it on a background isolate.
We recommend awaiting it in the main isolate, _before_ spawning a background isolate that might use the database.

### Providing a temporary path

If you have complex queries failing with a `SQLITE_IOERR_GETTEMPPATH 6410` error, you could try to explicitly set the
temporary path used by sqlite3. [This comment](https://github.com/simolus3/moor/issues/876#issuecomment-710013503) contains a snippet
to do just that.