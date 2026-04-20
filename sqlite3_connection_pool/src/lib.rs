use crate::client::PoolClient;
use crate::connection::PreparedStatement;
use crate::dart::DartPort;
use crate::pool::{ConnectionPool, PendingMessage, PoolConnection, PoolRequestHandle, PoolState};
use crate::registry::{PoolInitializer, PoolRegistry};
use std::ffi::{c_int, c_void};
use std::ptr::NonNull;
use std::sync::{Arc, Mutex};
use std::{ptr, slice};

mod client;
mod connection;
mod dart;
mod pool;
mod registry;
mod update_hook;

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_open(
    name: *const u8,
    name_len: usize,
    initialize: PoolInitializer,
) -> Option<NonNull<PoolClient>> {
    let name = unsafe { str::from_utf8_unchecked(slice::from_raw_parts(name, name_len)) };

    PoolRegistry::lookup(name, initialize).map(|pool| {
        let client = PoolClient::new(pool);

        unsafe { NonNull::new_unchecked(Box::into_raw(Box::new(client))) }
    })
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_close(pool: *mut PoolClient) {
    let pool = unsafe { Box::from_raw(pool) };
    drop(pool)
}

fn clone_arc(pool: &Mutex<PoolState>) -> ConnectionPool {
    let ptr = ptr::from_ref(pool);

    unsafe { Arc::increment_strong_count(ptr) };
    unsafe { Arc::from_raw(ptr) }
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_obtain_read(
    client: &PoolClient,
    tag: i64,
    port: DartPort,
) -> *mut PoolRequestHandle {
    let pool = &client.pool;
    let mut state = pool.lock().unwrap();
    let pool = clone_arc(pool);

    Box::into_raw(Box::new(
        state.request_read(pool, PendingMessage { tag, port }),
    ))
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_obtain_write(
    client: &PoolClient,
    tag: i64,
    port: DartPort,
) -> *mut PoolRequestHandle {
    let pool = &client.pool;
    let mut state = pool.lock().unwrap();
    let pool = clone_arc(pool);

    Box::into_raw(Box::new(
        state.request_write(pool, PendingMessage { tag, port }),
    ))
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_obtain_exclusive(
    client: &PoolClient,
    tag: i64,
    port: DartPort,
) -> *mut PoolRequestHandle {
    let pool = &client.pool;
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
    client: &PoolClient,
) -> usize {
    let state = client.pool.lock().unwrap();
    let (_, readers) = state.view_connections();
    readers.len()
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_query_connections(
    client: &PoolClient,
    writer: &mut *const PoolConnection,
    readers: *mut *const PoolConnection,
    reader_count: usize,
) {
    let state = client.pool.lock().unwrap();
    let (pool_writer, pool_readers) = state.view_connections();

    *writer = pool_writer;
    for (i, conn) in pool_readers.iter().enumerate() {
        if i >= reader_count {
            break;
        }

        unsafe { readers.add(i).write(conn) };
    }
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_update_listener(
    client: &mut PoolClient,
    add: bool,
    listener: DartPort,
) {
    if add {
        client.register_update_listener(listener)
    } else {
        client.remove_update_listener(listener)
    }
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_notify_updates(request: &PoolRequestHandle) {
    let pool = request.pool.lock().unwrap();
    unsafe {
        // Safety: Dart must only call this when owning a write connection.
        pool.send_update_notifications()
    };
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_stmt_cache_get(
    connection: &mut PoolConnection,
    sql: *const u8,
    sql_len: usize,
) -> Option<NonNull<c_void>> {
    let sql = unsafe { str::from_utf8_unchecked(slice::from_raw_parts(sql, sql_len)) };
    connection
        .cached_statements
        .as_mut()
        .and_then(|cache| cache.lookup(sql))
}

#[unsafe(no_mangle)]
extern "C" fn pkg_sqlite3_connection_pool_stmt_cache_put(
    connection: &mut PoolConnection,
    sql: *const u8,
    sql_len: usize,
    stmt: NonNull<c_void>,
    finalize: extern "C" fn(PreparedStatement) -> c_int,
) -> c_int {
    let sql = unsafe { str::from_utf8_unchecked(slice::from_raw_parts(sql, sql_len)) };
    if let Some(cache) = connection.cached_statements.as_mut() {
        cache.put(sql.to_owned(), PreparedStatement(stmt), finalize);
        1
    } else {
        0
    }
}
