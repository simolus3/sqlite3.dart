# sqlite3_flutter_libs

This package intentionally contains no Dart code. Flutter apps depending on this package will
contain native `sqlite3` libraries.

For more details on how to actually use this package in a Flutter app, see 
[sqlite3](https://pub.dev/packages/sqlite3).

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