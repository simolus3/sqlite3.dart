use crate::connection::Connection;
use crate::dart::{DartPort, RawDartCObject, RawDartCObjectArray, RawDartCObjectValue};
use crate::pool::ExternalFunctions;
use std::collections::HashSet;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::mem;
use std::ptr::NonNull;

#[derive(Default)]
pub struct CollectedTableUpdates {
    /// Tables that have been updated in the current transaction (that hasn't been committed yet).
    uncommitted_updates: HashSet<CString>,
    /// Tables that have been updated and committed but for which Dart clients have not been
    /// notified yet.
    ///
    /// We can't notify Dart clients directly in a commit hook because the notification then runs
    /// concurrently to the rest of the commit. So we might issue reads before the transaction is
    /// fully committed, causing stale data to get returned.
    outstanding_notification: HashSet<CString>,
}

impl CollectedTableUpdates {
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
        if !self.outstanding_notification.contains(table)
            && !self.uncommitted_updates.contains(table)
        {
            self.uncommitted_updates.insert(table.to_owned());
        }
    }

    fn handle_commit(&mut self) {
        for update in mem::take(&mut self.uncommitted_updates) {
            self.outstanding_notification.insert(update);
        }
    }

    fn handle_rollback(&mut self) {
        self.uncommitted_updates.clear()
    }

    pub fn send_notification(&mut self, listeners: &[DartPort], functions: &ExternalFunctions) {
        let updates = mem::take(&mut self.outstanding_notification);
        if updates.is_empty() {
            return;
        }

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
            (functions.dart_post_c_object)(*listener, &mut dart_msg);
        }
    }
}
