//
// Copyright 2023 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

use crate::common::*;
use crate::tokenize::signal_fts5_tokenize;
use alloc::boxed::Box;
use core::ffi::{c_char, c_int, c_uchar, c_void};
use core::ptr::null_mut;

pub const FTS5_API_VERSION: c_int = 2;

pub extern "C" fn signal_fts5_tokenizer_init(
    db: *mut Sqlite3,
    _pz_err_msg: *mut *mut c_uchar,
    p_api: *const c_void,
) -> c_int {
    match signal_fts_tokenizer_internal_init(db, p_api) {
        Ok(_) => SQLITE_OK,
        Err(code) => code,
    }
}

fn signal_fts_tokenizer_internal_init(db: *mut Sqlite3, p_api: *const c_void) -> Result<(), c_int> {
    if unsafe { sqlite3_libversion_number() } < 302000 {
        return Err(SQLITE_MISUSE);
    }

    let mut stmt = null_mut::<Sqlite3Stmt>();
    let rc = unsafe { sqlite3_prepare(db, c"SELECT fts5(?1)".as_ptr(), -1, &mut stmt, null_mut()) };

    if rc != SQLITE_OK {
        return Err(rc);
    }

    let mut p_fts5_api = null_mut::<FTS5API>();
    let rc = unsafe {
        sqlite3_bind_pointer(
            stmt,
            1,
            &mut p_fts5_api,
            b"fts5_api_ptr\0".as_ptr(),
            null_mut(),
        )
    };
    if rc != SQLITE_OK {
        unsafe { sqlite3_finalize(stmt) };
        return Err(rc);
    }

    // Intentionally ignore return value, sqlite3 returns SQLITE_ROW
    unsafe { sqlite3_step(stmt) };

    let rc = unsafe { sqlite3_finalize(stmt) };
    if rc != SQLITE_OK {
        return Err(rc);
    }

    let fts5_api = unsafe { p_fts5_api.as_ref() }.ok_or(SQLITE_INTERNAL)?;

    if fts5_api.i_version != FTS5_API_VERSION {
        return Err(SQLITE_MISUSE);
    }

    // Add custom tokenizer
    let mut tokenizer = Fts5TokenizerApi {
        x_create: fts5_create_signal_tokenizer,
        x_delete: fts5_delete_signal_tokenizer,
        x_tokenize: signal_fts5_tokenize,
    };

    (fts5_api.x_create_tokenizer)(
        fts5_api,
        b"signal_tokenizer\0".as_ptr(),
        null_mut(),
        &mut tokenizer,
        fts5_destroy_icu_module,
    );

    return Ok(());
}

pub extern "C" fn fts5_create_signal_tokenizer(
    _p_context: *mut c_void,
    _az_arg: *const *const c_uchar,
    _n_arg: c_int,
    fts5_tokenizer: *mut *mut Fts5Tokenizer,
) -> c_int {
    let tokenizer = Box::new(Fts5Tokenizer {});
    unsafe {
        *fts5_tokenizer = Box::into_raw(tokenizer);
    }
    return SQLITE_OK;
}

pub extern "C" fn fts5_delete_signal_tokenizer(fts5_tokenizer: *mut Fts5Tokenizer) {
    let tokenizer = unsafe { Box::from_raw(fts5_tokenizer) };
    drop(tokenizer);
}

pub extern "C" fn fts5_destroy_icu_module(_module: *mut c_void) {
    // no-op
}
