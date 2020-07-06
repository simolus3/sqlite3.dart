// Common result codes, https://www.sqlite.org/rescode.html

import 'dart:ffi';

const SQLITE_OK = 0;
const SQLITE_ROW = 100;
const SQLITE_DONE = 101;

// Flags for file open operations, https://www.sqlite.org/c3ref/c_open_autoproxy.html

const SQLITE_OPEN_READONLY = 0x00000001;
const SQLITE_OPEN_READWRITE = 0x00000002;
const SQLITE_OPEN_CREATE = 0x00000004;
const SQLITE_OPEN_URI = 0x00000040;
const SQLITE_OPEN_MEMORY = 0x00000080;
const SQLITE_OPEN_NOMUTEX = 0x00008000;
const SQLITE_OPEN_FULLMUTEX = 0x00010000;
const SQLITE_OPEN_SHAREDCACHE = 0x00020000;
const SQLITE_OPEN_PRIVATECACHE = 0x00040000;
const SQLITE_OPEN_NOFOLLOW = 0x01000000;

// Prepare flags, https://www.sqlite.org/c3ref/c_prepare_normalize.html
const SQLITE_PREPARE_PERSISTENT = 0x01;
const SQLITE_PREPARE_NO_VTAB = 0x04;

// Datatypes, https://sqlite.org/c3ref/c_blob.html

const SQLITE_INTEGER = 1;
const SQLITE_FLOAT = 2;
const SQLITE_TEXT = 3;
const SQLITE_BLOB = 4;
const SQLITE_NULL = 5;

// Text Encodings, https://www.sqlite.org/c3ref/c_any.html

const SQLITE_UTF8 = 1;

// Special destructors, https://www.sqlite.org/c3ref/c_static.html

Pointer<Void> SQLITE_TRANSIENT = Pointer.fromAddress(-1);

// Function flags, https://www.sqlite.org/c3ref/c_deterministic.html
const SQLITE_DETERMINISTIC = 0x000000800;
const SQLITE_DIRECTONLY = 0x000080000;
