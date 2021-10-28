# sqlcipher_flutter_libs

Flutter apps depending on this package will contain native `SQLCipher` libraries
on Android, iOS and macOS.

As `SQLCipher` has an ABI compatible to the regular `sqlite3` library, it can be used
with an unmodified `sqlite3` package.

## Using this package

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

## Incompatibilities with `sqlite3` on iOS and macOS

For iOS and macOS builds, depending on this package will install the `SQLCipher` pod.
When depending on another package linking the regular `sqlite3` pod or library, this can lead to undefined
behavior which may mean that __SQLCipher will not be available in your app__.
On such problematic package is `google_mobile_ads`.

To fix this problem, you can put `-framework SQLCipher` in "Other Linker Flags" in your project's settings
on XCode.
For more details on this, see

- [Important Advisory: SQLCipher with Xcode 8 and new SDKs](https://discuss.zetetic.net/t/important-advisory-sqlcipher-with-xcode-8-and-new-sdks/1688)
- [Cannot open encrypted database with SQLCipher 4](https://discuss.zetetic.net/t/cannot-open-encrypted-database-with-sqlcipher-4/3654/3)

## Problems on Android 6

There appears to be a problem when loading native libraries on Android 6 (see [this issue](https://github.com/simolus3/moor/issues/895#issuecomment-720195005)).
If you're seeing those crashes, you could try setting `android.bundle.enableUncompressedNativeLibs=false` in your `gradle.properties`
file. Be aware that this increases the size of your application when installed.

Alternatively, you can use the `applyWorkaroundToOpenSqlCipherOnOldAndroidVersions` method from this library.
It will try to open `sqlcipher` in Java, which seems to work more reliably. After the native library has been loaded from Java,
we can open it in Dart too.
The method should be called before using `sqlite3` (either directly or indirectly through say a `NativeDatabase` from `package:drift`).

As `applyWorkaroundToOpenSqlCipherOnOldAndroidVersions` uses platform channels, there may be issues when using it on a background isolate.
We recommend awaiting it in the main isolate, _before_ spawning a background isolate that might use the database.
