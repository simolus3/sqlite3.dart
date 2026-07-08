# sqlite3-web

Small, fast, convenient bindings for SQLite on the web.

## Features

By using a custom WebAssembly and worker build, this package provides access to SQLite on the web.
It's designed with a batteries-included approach, and provides:

1. Runtime feature detection: This package automatically picks a suitable database implementation (IndexedDB or OPFS)
   depending on what the current browser supports.
2. Automatic worker management: For performance, databases are accessed through web workers managed by this library.
3. APIs to access the underlying file system of the worker, which can be used to read and write to database files.
4. A fully-featured SQLite build, with fts5, rtree, math, dbstat and session extensions enabled by default.
5. Encryption support with SQLite3 Multiple Ciphers.

Before compression, the library itself is around 10 KB in size. Additionally, this includes a 225 KB
web worker and a 750 KB WebAssembly file for SQLite.

## Setup

This package needs access to a worker and a SQLite WebAssembly module. It exports those, but you are responsible for passing
resolved URLs (allowing you to integrate these assets into your build system).

If you're using vite, [explicit URL imports](https://vite.dev/guide/assets#explicit-url-imports) are what you need:

```TypeScript
import workerUrl from "sqlite3-web/worker.js?url";

// Or, if you need encryption support, `sqlite3-web/sqlite3mc.wasm?url`
import sqliteWasm from "sqlite3-web/sqlite3.wasm?url";

import { defaultWorkerConnector, openWebSqlite } from "sqlite3-web";

const sqlite3 = openWebSqlite({
  workers: defaultWorkerConnector(workerUrl),
  wasmUri: sqliteWasm,
});
```

## Opening databases

To open a database, use `connectToRecommended`:

```TypeScript
const db = await sqlite3.connectToRecommended("my_database");

await db.execute("CREATE TABLE users (name TEXT) STRICT");
const result = await db.select(
  "SELECT * FROM users LIMIT ?",
  { parameters: [10] }
);
```

### Encryption

Using encrypted databases is available via [SQLite3 Multiple Ciphers](https://utelle.github.io/SQLite3MultipleCiphers/).

To enable encryption:

1. Use the `sqlite3-web/sqlite3mc.wasm` export as a WebAssembly module.
2. When calling `connect()` or `connectToRecommended`, pass `enableEncryptedVfs: true`.
3. After opening the database, run a `pragma key = ` to configure encryption. Different options are [documented here](https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql/), note that this package only supports the `ChaCha20-Poly1305` scheme.

## Local development

Working on this package requires a [Dart SDK](https://dart.dev/) installation. Run `dart pub get` in the repository
and `pnpm install` in `sqlite3_web/extra/js-package`.

To download the WebAssembly files from the latest release, use `pnpm wasm:download`.
To compile them yourself, see [this directory](https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3_wasm_build).

To build the worker, run `pnpm build:worker`. Finally, `pnpm build` builds and bundles TypeScript sources and
`pnpm test` tests the package.
