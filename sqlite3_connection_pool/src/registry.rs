use crate::connection::Connection;
use crate::pool::{ConnectionPool, ExternalFunctions, PoolState};
use std::collections::HashMap;
use std::ptr::NonNull;
use std::slice;
use std::sync::{Arc, LazyLock, Mutex, Weak};

static REGISTRY: LazyLock<PoolRegistry> = LazyLock::new(|| PoolRegistry::default());

#[derive(Default)]
pub struct PoolRegistry {
    pools: Mutex<HashMap<String, Weak<Mutex<PoolState>>>>,
}

#[repr(C)]
pub struct InitializedPool {
    functions: ExternalFunctions,
    write: Connection,
    reads: *const Connection,
    read_count: usize,
}

pub type PoolInitializer = extern "C" fn() -> Option<NonNull<InitializedPool>>;

impl PoolRegistry {
    fn lookup_internal(&self, name: &str, initialize: PoolInitializer) -> Option<ConnectionPool> {
        let mut pools = self.pools.lock().unwrap();
        if let Some(pool) = pools.get(name) {
            if let Some(pool) = Weak::upgrade(pool) {
                return Some(pool);
            }
        };

        // The pool doesn't exist, obtain connections from Dart callback.
        let Some(initialized) = initialize() else {
            // Initialization failed, don't insert a pool.
            return None;
        };
        let initialized = unsafe {
            // The returned pointer is valid until this function returns.
            initialized.as_ref()
        };

        let state = PoolState::new(initialized.functions, initialized.write, unsafe {
            slice::from_raw_parts(initialized.reads, initialized.read_count)
        });

        let pool = ConnectionPool::new(Mutex::new(state));
        pools.insert(name.to_string(), Arc::downgrade(&pool));
        Some(pool)
    }

    pub fn lookup(name: &str, initialize: PoolInitializer) -> Option<ConnectionPool> {
        REGISTRY.lookup_internal(name, initialize)
    }
}
