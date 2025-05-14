//
// Copyright 2023 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

use core::ffi::{c_char, c_int, c_uchar, c_void};

pub struct Fts5Tokenizer {}

// sqlite3.h
pub const SQLITE_OK: c_int = 0;
pub const SQLITE_INTERNAL: c_int = 2;
pub const SQLITE_MISUSE: c_int = 21;

#[repr(C)]
pub struct Sqlite3 {
    _private: [u8; 0],
}

#[repr(C)]
pub struct Sqlite3Stmt {
    _private: [u8; 0],
}

pub type TokenFunction = extern "C" fn(
    p_ctx: *mut c_void,
    t_flags: c_int,
    p_token: *const c_char,
    n_token: c_int,
    i_start: c_int,
    i_end: c_int,
) -> c_int;

// fts5.h
#[repr(C)]
pub struct Fts5TokenizerApi {
    pub x_create: extern "C" fn(
        p_context: *mut c_void,
        az_arg: *const *const c_uchar,
        n_arg: c_int,
        fts5_tokenizer: *mut *mut Fts5Tokenizer,
    ) -> c_int,
    pub x_delete: extern "C" fn(fts5_tokenizer: *mut Fts5Tokenizer),
    pub x_tokenize: extern "C" fn(
        tokenizer: *mut Fts5Tokenizer,
        p_ctx: *mut c_void,
        flags: c_int,
        p_text: *const c_char,
        n_text: c_int,
        x_token: TokenFunction,
    ) -> c_int,
}

#[repr(C)]
pub struct FTS5API {
    pub i_version: c_int, // Currently always set to 2

    /* Create a new tokenizer */
    pub x_create_tokenizer: extern "C" fn(
        fts5_api: *const FTS5API,
        z_name: *const c_uchar,
        p_context: *mut c_void,
        fts5_tokenizer: *mut Fts5TokenizerApi,
        x_destroy: extern "C" fn(module: *mut c_void),
    ) -> c_int,
}

extern "C" {
    pub fn sqlite3_malloc(size: c_int) -> *mut c_void;
    pub fn sqlite3_free(ptr: *const c_void);

    pub fn sqlite3_libversion_number() -> c_int;

    pub fn sqlite3_prepare(
        db: *mut Sqlite3,
        zSql: *const c_char,
        length: c_int,
        stmt: *mut *mut Sqlite3Stmt,
        ppzTail: *mut *const c_char,
    ) -> c_int;

    pub fn sqlite3_bind_pointer(
        stmt: *mut Sqlite3Stmt,
        index: c_int,
        ptr: *mut *mut FTS5API,
        name: *const c_uchar,
        cb: *mut c_void,
    ) -> c_int;

    pub fn sqlite3_finalize(stmt: *mut Sqlite3Stmt) -> c_int;

    pub fn sqlite3_step(stmt: *mut Sqlite3Stmt) -> c_int;

    pub fn sqlite3_auto_extension(
        entrypoint: extern "C" fn(
            db: *mut Sqlite3,
            _pz_err_msg: *mut *mut c_uchar,
            p_api: *const c_void,
        ) -> c_int,
    ) -> c_int;
}
