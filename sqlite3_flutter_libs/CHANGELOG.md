## 0.5.17

- Upgrade sqlite to version `3.43.1`.

## 0.5.16

- Upgrade sqlite to version `3.43.0`.

## 0.5.15

- Upgrade sqlite to version `3.41.2`.

## 0.5.14

- Support Android projects built with Gradle 8.

## 0.5.13

- Upgrade sqlite to version `3.41.0`.

## 0.5.12

- Upgrade sqlite to version `3.40.0`.


## 0.5.11+1

- Upgrade sqlite3 to version `3.39.4`.
- Fix a compilation warning on Windows.
- Stop bundling `spellfix1` on platforms where that was still the case by
  default.

## 0.5.10

- Upgrade sqlite to version `3.39.3`.
- Consistently compile sqlite3 with `-DSQLITE_THREADSAFE=1` on all platforms.

## 0.5.9

- Upgrade sqlite to version `3.39.2`.

## 0.5.8

- Upgrade sqlite to version `3.39.0`

## 0.5.7

- Update sqlite to version `3.38.5`

## 0.5.6

- Update sqlite to version `3.38.3`

## 0.5.5

- Update sqlite to version `3.38.2`
- Linux is now supported without additional setup.
- Windows is now supported without additional setup.

## 0.5.4

- Update sqlite to version `3.38.0`

## 0.5.3

- Update sqlite to version `3.37.2`

## 0.5.2

- Update sqlite to version `3.37.0`

## 0.5.1

- Update sqlite to version `3.36.0`

## 0.5.0

- Also include sqlite when building for macOS

## 0.4.3

- Upgrade to sqlite3 version 3.35.4 on iOS as well

## 0.4.2

- Upgrade to sqlite3 version 3.35.4 on Android

## 0.4.1

- Raise minimum SDK constraint to Dart 2.12

## 0.4.0

`0.4.0+1` fixes an issue causing sqlite3 libraries to be unavailable in the
compiled app. Please don't use `0.4.0`!

- Migrate native Android dependencies away from Bintray

## 0.3.0

- Add workaround for an apparent loader bug in Android 6.0.1 (see readme for details)

## 0.2.0

- Use ObjectiveC instead of Swift for the iOS plugin

## 0.1.0

- Add an empty Dart library to improve the pub score

## 0.0.1

- Initial release
