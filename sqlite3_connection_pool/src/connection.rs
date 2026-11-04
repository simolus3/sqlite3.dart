use crate::pool::ExternalFunctions;
use lru::LruCache;
use std::ffi::{c_int, c_void};
use std::num::NonZeroUsize;
use std::ptr::NonNull;

#[derive(Copy, Clone)]
#[repr(transparent)]
pub struct Connection(pub *const c_void);

unsafe impl Send for Connection {}
unsafe impl Sync for Connection {}

#[derive(Copy, Clone, PartialEq, Eq)]
#[repr(transparent)]
pub struct PreparedStatement(pub NonNull<c_void>);

unsafe impl Send for PreparedStatement {}
unsafe impl Sync for PreparedStatement {}

pub struct StatementCache {
    cache: LruCache<String, PreparedStatement>,
}

impl StatementCache {
    pub fn new(size: usize) -> Option<Self> {
        Some(Self {
            cache: LruCache::new(NonZeroUsize::new(size)?),
        })
    }

    pub fn lookup(&mut self, sql: &str) -> Option<NonNull<c_void>> {
        self.cache.get(sql).map(|p| p.0)
    }

    pub fn put(
        &mut self,
        sql: String,
        stmt: PreparedStatement,
        finalize: extern "C" fn(PreparedStatement) -> c_int,
    ) {
        if let Some((_, old)) = self.cache.push(sql, stmt) {
            if old != stmt {
                // We had to remove an older statement from the cache to make room for the new one.
                // Properly finalize that statement now.
                finalize(old);
            }
        }
    }

    pub fn close_statements(&mut self, functions: &ExternalFunctions) {
        for (_, stmt) in self.cache.iter() {
            (functions.sqlite3_finalize)(*stmt);
        }

        self.cache.clear()
    }
}
