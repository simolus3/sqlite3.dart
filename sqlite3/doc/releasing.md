## Releasing `package:sqlite3`.

Because each release contains native SQLite binaries whose hashes are referenced in Dart,
adding a new release requires some setup.

1. Run the full actions test pipeline for all changes to include.
2. From that run, download the `asset_hashes.dart` file and copy it to
   `sqlite3/lib/src/hook/asset_hashes.dart`.
3. In that file, set `releaseTag` to `sqlite3-<$newVersion>`.
4. In `sqlite3/pubspec.yaml`, set `version` to `$newVersion`.
5. Commit and create a git tag `sqlite3-<$newVersion>`.
6. Push that tag and approve the pub.dev publishing workflow.
