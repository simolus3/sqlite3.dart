use crate::connection::Connection;
use crate::dart::DartPort;
use crate::pool::{ConnectionPool, PendingMessage, PoolRequestHandle, PoolState};
use crate::registry::{PoolInitializer, PoolRegistry};
use std::mem::MaybeUninit;
use std::ptr::NonNull;
use std::sync::{Arc, Mutex};
use std::{ptr, slice};

mod connection;
mod dart;
mod pool;
mod registry;

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_open(
    name: *const u8,
    name_len: usize,
    initialize: PoolInitializer,
) -> Option<NonNull<Mutex<PoolState>>> {
    let name = unsafe { str::from_utf8_unchecked(slice::from_raw_parts(name, name_len)) };

    PoolRegistry::lookup(name, initialize)
        .map(|pool| unsafe { NonNull::new_unchecked(Arc::into_raw(pool).cast_mut()) })
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_close(pool: *const Mutex<PoolState>) {
    let pool: ConnectionPool = unsafe { Arc::from_raw(pool) };
    drop(pool)
}

fn clone_arc(pool: &Mutex<PoolState>) -> ConnectionPool {
    let ptr = ptr::from_ref(pool);

    unsafe { Arc::increment_strong_count(ptr) };
    unsafe { Arc::from_raw(ptr) }
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_obtain_read(
    pool: &Mutex<PoolState>,
    tag: i64,
    port: DartPort,
) -> *mut PoolRequestHandle {
    let mut state = pool.lock().unwrap();
    let pool = clone_arc(pool);

    Box::into_raw(Box::new(
        state.request_read(pool, PendingMessage { tag, port }),
    ))
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_obtain_write(
    pool: &Mutex<PoolState>,
    tag: i64,
    port: DartPort,
) -> *mut PoolRequestHandle {
    let mut state = pool.lock().unwrap();
    let pool = clone_arc(pool);

    Box::into_raw(Box::new(
        state.request_write(pool, PendingMessage { tag, port }),
    ))
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_obtain_exclusive(
    pool: &Mutex<PoolState>,
    tag: i64,
    port: DartPort,
) -> *mut PoolRequestHandle {
    let mut state = pool.lock().unwrap();
    let pool = clone_arc(pool);

    Box::into_raw(Box::new(
        state.request_exclusive(pool, PendingMessage { tag, port }),
    ))
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_request_close(request: *mut PoolRequestHandle) {
    drop(unsafe { Box::from_raw(request) });
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_query_read_connection_count(
    pool: &Mutex<PoolState>,
) -> usize {
    let state = pool.lock().unwrap();
    let (_, readers) = state.view_connections();
    readers.len()
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_query_connections(
    pool: &Mutex<PoolState>,
    writer: &mut MaybeUninit<Connection>,
    readers: *mut Connection,
    reader_count: usize,
) {
    let state = pool.lock().unwrap();
    let (pool_writer, pool_readers) = state.view_connections();

    writer.write(*pool_writer);
    for (i, conn) in pool_readers.iter().enumerate() {
        if i >= reader_count {
            break;
        }

        unsafe { readers.add(i).write(*conn) };
    }
}
