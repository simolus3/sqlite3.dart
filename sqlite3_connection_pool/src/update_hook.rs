use crate::connection::Connection;
use crate::dart::{RawDartCObject, RawDartCObjectArray, RawDartCObjectValue};
use crate::pool::{ExternalFunctions, PoolState};
use std::collections::HashSet;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::mem;
use std::ptr::NonNull;
use std::sync::{Arc, Mutex, Weak};

pub struct CollectedTableUpdates {
    /// Tables that have been updated since the last recorded commit.
    updated_since_last_commit: HashSet<CString>,
    pool: Weak<Mutex<PoolState>>,
}

impl CollectedTableUpdates {
    pub fn new(pool: &Arc<Mutex<PoolState>>) -> Self {
        Self {
            updated_since_last_commit: Default::default(),
            pool: Arc::downgrade(pool),
        }
    }

    pub fn attach_to(
        ptr: *mut CollectedTableUpdates,
        functions: &ExternalFunctions,
        connection: Connection,
    ) {
        extern "C" fn update_hook(
            context: NonNull<c_void>,
            _write_kind: c_int,
            _database: *const c_char,
            table: *const c_char,
            _rowid: i64,
        ) {
            let table = unsafe { CStr::from_ptr(table) };
            let context = unsafe { context.cast::<CollectedTableUpdates>().as_mut() };
            context.handle_update(table)
        }

        extern "C" fn rollback_hook(context: NonNull<c_void>) {
            let context = unsafe { context.cast::<CollectedTableUpdates>().as_mut() };
            context.handle_rollback()
        }

        extern "C" fn commit_hook(context: NonNull<c_void>) -> c_int {
            let context = unsafe { context.cast::<CollectedTableUpdates>().as_mut() };
            context.handle_commit();
            // Returning zero makes the COMMIT operation continue normally.
            0
        }

        (functions.sqlite3_update_hook)(connection, Some(update_hook), ptr.cast());
        (functions.sqlite3_commit_hook)(connection, Some(commit_hook), ptr.cast());
        (functions.sqlite3_rollback_hook)(connection, Some(rollback_hook), ptr.cast());
    }

    fn handle_update(&mut self, table: &CStr) {
        if !self.updated_since_last_commit.contains(table) {
            self.updated_since_last_commit.insert(table.to_owned());
        }
    }

    fn handle_commit(&mut self) {
        let updates = mem::take(&mut self.updated_since_last_commit);
        if updates.is_empty() {
            return;
        }

        let Some(pool) = self.pool.upgrade() else {
            return;
        };
        let pool = pool.lock().unwrap();
        let listeners = pool.update_listeners();
        if listeners.is_empty() {
            return;
        }

        let mut dart_strings: Vec<RawDartCObject> = Vec::with_capacity(updates.len());
        for update in &updates {
            dart_strings.push(RawDartCObject {
                type_: RawDartCObject::TYPE_STRING,
                value: RawDartCObjectValue {
                    as_string: update.as_c_str().as_ptr(),
                },
            });
        }
        let mut dart_string_references: Vec<*mut RawDartCObject> = dart_strings
            .iter()
            .map(|d| d as *const _ as *mut _)
            .collect();

        // Create Dart list of strings.
        let mut dart_msg = RawDartCObject {
            type_: RawDartCObject::TYPE_ARRAY,
            value: RawDartCObjectValue {
                as_array: RawDartCObjectArray {
                    length: dart_string_references.len() as isize,
                    values: dart_string_references.as_mut_ptr(),
                },
            },
        };

        // Send to registered update ports.
        for listener in listeners {
            (pool.functions.dart_post_c_object)(*listener, &mut dart_msg);
        }
    }

    fn handle_rollback(&mut self) {
        self.updated_since_last_commit.clear()
    }
}
