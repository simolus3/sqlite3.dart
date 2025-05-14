//
// Copyright 2023 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

use core::ffi::{c_char, c_int, c_uchar, c_void};

use alloc::string::String;
use unicode_normalization::UnicodeNormalization;
use unicode_segmentation::UnicodeSegmentation;

use crate::common::{Fts5Tokenizer, TokenFunction, SQLITE_OK};

pub extern "C" fn signal_fts5_tokenize(
    _tokenizer: *mut Fts5Tokenizer,
    p_ctx: *mut c_void,
    _flags: c_int,
    p_text: *const c_char,
    n_text: c_int,
    x_token: TokenFunction,
) -> c_int {
    match signal_fts5_tokenize_internal(p_ctx, p_text, n_text, x_token) {
        Ok(()) => SQLITE_OK,
        Err(code) => code,
    }
}

fn signal_fts5_tokenize_internal(
    p_ctx: *mut c_void,
    p_text: *const c_char,
    n_text: c_int,
    x_token: TokenFunction,
) -> Result<(), c_int> {
    let slice = unsafe { core::slice::from_raw_parts(p_text as *const c_uchar, n_text as usize) };

    // Map errors to SQLITE_OK because failing here means that the database
    // wouldn't accessible.
    let input = core::str::from_utf8(slice).map_err(|_| SQLITE_OK)?;

    let mut normalized = String::with_capacity(1024);

    for (off, segment) in input.unicode_word_indices() {
        normalize_into(segment, &mut normalized);
        let rc = x_token(
            p_ctx,
            0,
            normalized.as_bytes().as_ptr() as *const c_char,
            normalized.len() as c_int,
            off as c_int,
            (off + segment.len()) as c_int,
        );
        if rc != SQLITE_OK {
            return Err(rc);
        }
    }

    return Ok(());
}

fn is_diacritic(x: char) -> bool {
    '\u{0300}' <= x && x <= '\u{036f}'
}

fn normalize_into(segment: &str, buf: &mut String) {
    buf.clear();

    for x in segment.nfd() {
        if is_diacritic(x) {
            continue;
        }
        if x.is_ascii() {
            buf.push(x.to_ascii_lowercase());
        } else {
            buf.extend(x.to_lowercase());
        }
    }
}
