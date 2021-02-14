## 1.0.0

- Support version `1.0.0` of `package:ffi`

## 0.1.10-nullsafety.0

- Support version `0.3.0` of `package:ffi`
- Migrate library to support breaking ffi changes in Dart 2.13:
  - Use `Opaque` instead of empty structs
  - Use `Allocator` api

## 0.1.9-nullsafety.2

- Fix loading sqlite3 on iOS

## 0.1.9-nullsafety.1

- Migrate package to null safety

## 0.1.8

- Added the `mutex` parameter to control the serialization mode
  when opening databases.

## 0.1.7

- Expose the `sqlite3_temp_directory` global variable

## 0.1.6

- Expose underlying database and statement handles
- Support opening databases from uris

## 0.1.5

- Use `sqlite3_version` to determine if `sqlite3_prepare_v3` is available
  instead of catching an error.

## 0.1.4

- Use `sqlite3_prepare_v2` if `sqlite3_prepare_v3` is not available

## 0.1.3

- Lower minimum version requirement on `collection` to `^1.14.0`

## 0.1.2

- Enable extended result codes
- Expose raw rows from a `ResultSet`

## 0.1.1

- Expose the `ResultSet` class

## 0.1.0

- Initial version
