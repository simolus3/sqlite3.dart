# sqlcipher_flutter_libs

Flutter apps depending on this package will contain native `SQLCipher` libraries
on Android, iOS and macOS.

### Using this package

When using this package on Android, you need to tell the `sqlite3` package
how to open `sqlcipher` since it will attempt to open the regular
`sqlite3` binary by default:

```dart
import 'package:sqlite3/open.dart';

// Do this before using any sqlite3 api
open.overrideFor(
    OperatingSystem.android, openCipherOnAndroid);
```

You will also need to do this when using a package wrapping the `sqlite3`
package like `moor` or `sqflite_common_ffi`!

__No changes are necessary for iOS and MacOS__

For more details on how to actually use this package in a Flutter app, see 
[sqlite3](https://pub.dev/packages/sqlite3).


### Problems on Android 6

There appears to be a problem when loading native libraries on Android 6 (see [this issue](https://github.com/simolus3/moor/issues/895#issuecomment-720195005)).
If you're seeing those crashes, you could try setting `android.bundle.enableUncompressedNativeLibs=false` in your `gradle.properties`
file. Be aware that this increases the size of your application when installed.

Alternatively, you can use the `applyWorkaroundToOpenSqlCipherOnOldAndroidVersions` method from this library.
It will try to open `sqlcipher` in Java, which seems to work more reliably. After the native library has been loaded from Java,
we can open it in Dart too.
