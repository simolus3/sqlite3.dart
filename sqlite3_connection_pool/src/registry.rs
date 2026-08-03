use crate::connection::Connection;
use crate::pool::{ConnectionPool, ExternalFunctions, PoolState};
use std::collections::HashMap;
use std::ffi::c_uchar;
use std::slice;
use std::sync::{Arc, LazyLock, Mutex, MutexGuard, Weak};

static REGISTRY: LazyLock<PoolRegistry> = LazyLock::new(|| PoolRegistry::default());

#[derive(Default)]
pub struct PoolRegistry {
    pools: Mutex<HashMap<String, Weak<Mutex<PoolState>>>>,
}

pub struct UninitializedPool<'a> {
    name: &'a str,
    guard: MutexGuard<'a, HashMap<String, Weak<Mutex<PoolState>>>>,
}

pub enum MaybeInitializedPool<'a> {
    Pool(ConnectionPool),
    Uninitialized(UninitializedPool<'a>),
}

#[repr(C)]
pub struct InitializedPool {
    functions: ExternalFunctions,
    write: Connection,
    reads: *const Connection,
    read_count: usize,
    prepared_statement_cache_size: usize,
    enable_update_hooks: c_uchar,
}

impl PoolRegistry {
    fn lookup_internal<'a>(&'a self, name: &'a str) -> MaybeInitializedPool<'a> {
        let pools = self.pools.lock().unwrap();
        if let Some(pool) = pools.get(name) {
            if let Some(pool) = Weak::upgrade(pool) {
                return MaybeInitializedPool::Pool(pool);
            }
        };

        return MaybeInitializedPool::Uninitialized(UninitializedPool { name, guard: pools });
    }

    pub fn lookup<'a>(name: &'a str) -> MaybeInitializedPool<'a> {
        REGISTRY.lookup_internal(name)
    }
}

impl<'a> UninitializedPool<'a> {
    pub fn initialize(mut self, initialized: &InitializedPool) -> ConnectionPool {
        let state = PoolState::new(
            initialized.functions,
            initialized.write,
            unsafe { slice::from_raw_parts(initialized.reads, initialized.read_count) },
            initialized.prepared_statement_cache_size,
            initialized.enable_update_hooks != 0,
        );

        let pool = ConnectionPool::new(Mutex::new(state));
        PoolState::register_hooks_on_writer(&pool);

        self.guard
            .insert(self.name.to_string(), Arc::downgrade(&pool));
        pool
    }
}
