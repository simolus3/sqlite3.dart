use crate::connection::Connection;
use crate::dart::{self, FunctionError};
use crate::pool::{ConnectionPool, DartLinkData, ExternalFunctions, PoolAndFunctions, PoolState};
use std::collections::HashMap;
use std::ffi::c_uchar;
use std::slice;
use std::sync::{Arc, LazyLock, Mutex, MutexGuard, Weak};

static REGISTRY: LazyLock<PoolRegistry> = LazyLock::new(|| PoolRegistry::default());

#[derive(Default)]
pub struct PoolRegistry {
    pools: Mutex<HashMap<String, Weak<PoolAndFunctions>>>,
}

pub struct UninitializedPool<'a> {
    name: &'a str,
    guard: MutexGuard<'a, HashMap<String, Weak<PoolAndFunctions>>>,
}

pub enum MaybeInitializedPool<'a> {
    Pool(ConnectionPool),
    Uninitialized(UninitializedPool<'a>),
}

#[repr(C)]
pub struct InitializedPool {
    functions: DartLinkData,
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

        MaybeInitializedPool::Uninitialized(UninitializedPool { name, guard: pools })
    }

    pub fn lookup<'a>(name: &'a str) -> MaybeInitializedPool<'a> {
        REGISTRY.lookup_internal(name)
    }
}

impl<'a> UninitializedPool<'a> {
    pub fn initialize(
        mut self,
        initialized: &InitializedPool,
    ) -> Result<ConnectionPool, FunctionError> {
        let reads = unsafe { slice::from_raw_parts(initialized.reads, initialized.read_count) };
        let dart_functions =
            match unsafe { dart::Functions::initialize(initialized.functions.dart_api_data) } {
                Ok(functions) => functions,
                Err(e) => {
                    // Dart has given up ownership of these connections, so close them here to
                    // avoid leaking them.
                    let close = initialized.functions.sqlite.sqlite3_close_v2;
                    close(initialized.write);
                    for read in reads {
                        close(*read);
                    }

                    return Err(e);
                }
            };
        let state = PoolState::new(
            ExternalFunctions {
                sqlite: initialized.functions.sqlite,
                dart: dart_functions,
            },
            initialized.write,
            reads,
            initialized.prepared_statement_cache_size,
            initialized.enable_update_hooks != 0,
        );

        let pool = Arc::new(PoolAndFunctions {
            state: Mutex::new(state),
            dart: dart_functions,
        });
        PoolState::register_hooks_on_writer(&pool);

        self.guard
            .insert(self.name.to_string(), Arc::downgrade(&pool));
        Ok(pool)
    }
}
