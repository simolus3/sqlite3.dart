## Upgrading

To upgrade `sqlite3`, change the following versions:

- The dependency in `sqlite3_flutter_libs/android/build.gradle`
- The pod in `sqlite3_flutter_libs/ios/sqlite3_flutter_libs.podspec`
- The pod in `sqlite3_flutter_libs/macos/sqlite3_flutter_libs.podspec`

To upgrade `sqlcipher`, change the following versions:

- The dependency in `sqlcipher_flutter_libs/android/build.gradle`
- The pod in `sqlcipher_flutter_libs/ios/sqlcipher_flutter_libs.podspec`
- The pod in `sqlcipher_flutter_libs/macos/sqlcipher_flutter_libs.podspec`

Android, iOS and macOS should all have the same dependencies when publishing a
new version!
