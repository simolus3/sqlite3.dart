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
