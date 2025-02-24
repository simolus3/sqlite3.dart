## Upgrading

To upgrade `sqlite3`, change the following versions:

- The download URI in `sqlite3_native_assets/hook/build.dart`.
- The pod in `sqlite3_flutter_libs/darwin`.
- The SwiftPM reference in `sqlite3_flutter_libs/darwin`.
- The maven dependency in `sqlite3_flutter_libs/android/build.gradle`.
- The download URIs in `sqlite3_flutter_libs/windows` and `sqlite3_flutter_libs/linux`.
- The download URI in `sqlite3/assets/wasm/CMakeLists.txt`.

To upgrade `sqlcipher`, change the following versions:

- The dependency in `sqlcipher_flutter_libs/android/build.gradle`
- The pod in `sqlcipher_flutter_libs/ios/sqlcipher_flutter_libs.podspec`
- The pod in `sqlcipher_flutter_libs/macos/sqlcipher_flutter_libs.podspec`

Android, iOS and macOS should all have the same dependencies when publishing a
new version!
