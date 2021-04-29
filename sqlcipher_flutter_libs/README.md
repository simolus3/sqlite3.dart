# sqlcipher_flutter_libs

Flutter apps depending on this package will
contain native `SQLCipher` libraries.

### working with Android
  on android you need to override the open method like this

```dart
  open.overrideFor(
      OperatingSystem.android, openCipherOnAndroid);
```

__No changes are necessary for iOS__

For more details on how to actually use this package in a Flutter app, see 
[sqlite3](https://pub.dev/packages/sqlite3).


### Problems on Android 6

There appears to be a problem when loading native libraries on Android 6 (see [this issue](https://github.com/simolus3/moor/issues/895#issuecomment-720195005)).
If you're seeing those crashes, you could try setting `android.bundle.enableUncompressedNativeLibs=false` in your `gradle.properties`
file. Be aware that this increases the size of your application when installed.

Alternatively, you can use the `applyWorkaroundToOpenSqlCipherOnOldAndroidVersions` method from this library.
It will try to open `sqlcipher` in Java, which seems to work more reliably. After the native library has been loaded from Java,
we can open it in Dart too.
