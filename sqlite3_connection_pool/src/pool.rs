use crate::connection::{Connection, PreparedStatement, StatementCache};
use crate::dart::{DartPort, RawDartCObject, RawDartCObjectArray, RawDartCObjectValue};
use crate::update_hook::CollectedTableUpdates;
use std::cell::UnsafeCell;
use std::collections::VecDeque;
use std::ffi::{c_char, c_int, c_void};
use std::marker::PhantomData;
use std::ptr::NonNull;
use std::sync::{Arc, Mutex};

/// A connection pool can be locked, in which case some Dart actor has exclusive access to all
/// connections. When a new pool is initialized, it is also in this state.
pub type ConnectionPool = Arc<Mutex<PoolState>>;

pub struct PoolState {
    reads: ReadState,
    writes: WriteState,

    /// Function pointers provided from Dart when initializing the pool.
    ///
    /// We assume those to be static within a process, so we don't need to track them on a
    /// per-client basis.
    pub functions: ExternalFunctions,
    /// Safety: The context having a write connection lease is assumed to have a mutable reference
    /// to the updates collector.
    ///
    /// This allows not locking in update hooks (since the SQLite connection is never used
    /// concurrently).
    table_updates: Option<UnsafeCell<CollectedTableUpdates>>,
    update_listeners: Vec<DartPort>,
}

#[repr(C)]
pub struct PoolConnection {
    /// The raw `sqlite3*` connection pointer.
    pub raw: Connection,
    /// If statement caches are enabled, an LRU cache storing prepared statements by their SQL text.
    pub cached_statements: Option<StatementCache>,
}

struct ReadState {
    connections: Vec<PoolConnection>,
    idle_connections: VecDeque<usize>,
    waiters: LinkedList<Self>,
}

struct WriteState {
    connection: PoolConnection,
    acquired: bool,
    waiters: LinkedList<Self>,
}

struct LinkedList<E: ExtractEntry> {
    first: Option<NonNull<WaitNode>>,
    last: Option<NonNull<WaitNode>>,
    _e: PhantomData<E>,
}

unsafe impl<E: ExtractEntry> Send for LinkedList<E> {}
unsafe impl<E: ExtractEntry> Sync for LinkedList<E> {}

/// A node waiting for access to the connection pool.
///
/// A single node can be part of both the read and the write queue of a pool.
struct WaitNode {
    /// If this node is part of the read queue, pointers to the next and previous entry.
    read_entry: Option<QueueEntry>,
    /// If this node is part of the write queue, pointers to the next and previous entry.
    write_entry: Option<QueueEntry>,

    /// The message to send to the Dart client once the connection is obtained.
    port: PendingMessage,
    waiter: Waiter,
}

pub struct PendingMessage {
    pub tag: i64,
    pub port: DartPort,
}

struct QueueEntry {
    prev: Option<NonNull<WaitNode>>,
    next: Option<NonNull<WaitNode>>,
}

// These are only mutated when we have a mutex on the pool, so we can pretend they're send and sync.
unsafe impl Send for QueueEntry {}
unsafe impl Sync for QueueEntry {}

enum Waiter {
    Reader(ReadPoolRequest),
    Writer(WritePoolRequest),
    Exclusive(ExclusivePoolRequest),
}

#[derive(Default)]
struct ReadPoolRequest {
    assigned_connection: Option<usize>,
}

#[derive(Default)]
struct WritePoolRequest {
    has_writer: bool,
}

#[derive(Default)]
struct ExclusivePoolRequest {
    has_writer: bool,
    obtained_read_connections: usize,
}

impl PoolState {
    pub fn new(
        functions: ExternalFunctions,
        writer: Connection,
        reads: &[Connection],
        cache_size: usize,
    ) -> Self {
        let wrap_connection = |conn: Connection| -> PoolConnection {
            PoolConnection {
                raw: conn,
                cached_statements: StatementCache::new(cache_size),
            }
        };

        Self {
            reads: ReadState {
                idle_connections: (0usize..reads.len()).collect(),
                connections: reads.iter().copied().map(wrap_connection).collect(),
                waiters: Default::default(),
            },
            writes: WriteState {
                connection: wrap_connection(writer),
                acquired: false,
                waiters: Default::default(),
            },
            functions,
            table_updates: Default::default(),
            update_listeners: Default::default(),
        }
    }

    unsafe fn drop_waiter(&mut self, waiter: NonNull<WaitNode>) {
        let mut waiter = unsafe { Box::from_raw(waiter.as_ptr()) };
        let as_mut = waiter.as_mut();

        // Remove waiter from queue
        if as_mut.read_entry.is_some() {
            self.reads.waiters.unlink(as_mut);
        }
        if as_mut.write_entry.is_some() {
            self.writes.waiters.unlink(as_mut);
        }

        // Return resources owned by waiter
        match waiter.waiter {
            Waiter::Reader(ref reader) => {
                if let Some(ref connection) = reader.assigned_connection {
                    self.return_read_connection(*connection);
                }
            }
            Waiter::Writer(ref writer) => {
                if writer.has_writer {
                    self.return_write_connection();
                }
            }
            Waiter::Exclusive(ref exclusive) => {
                if exclusive.has_writer {
                    self.return_write_connection()
                }
                for i in 0..self.reads.connections.len() {
                    self.return_read_connection(i)
                }
            }
        }
    }

    fn return_read_connection(&mut self, conn: usize) {
        self.reads.idle_connections.push_back(conn);

        if let Some(mut waiting) = self.reads.waiters.first {
            let waiter = unsafe { waiting.as_mut() };
            let did_complete = self.try_complete(waiter);
            if did_complete {
                self.reads.waiters.unlink(waiter);
            }
        }
    }

    fn return_write_connection(&mut self) {
        self.writes.acquired = false;

        // See if we can complete the next writer.
        if let Some(mut waiting) = self.writes.waiters.first {
            let waiter = unsafe { waiting.as_mut() };
            let did_complete = self.try_complete(waiter);
            if did_complete {
                self.writes.waiters.unlink(waiter);
            }
        }
    }

    pub fn request_read(&mut self, pool: ConnectionPool, msg: PendingMessage) -> PoolRequestHandle {
        self.register_waiter(pool, msg, Waiter::Reader(Default::default()), true, false)
    }

    pub fn request_write(
        &mut self,
        pool: ConnectionPool,
        msg: PendingMessage,
    ) -> PoolRequestHandle {
        self.register_waiter(pool, msg, Waiter::Writer(Default::default()), false, true)
    }

    pub fn request_exclusive(
        &mut self,
        pool: ConnectionPool,
        msg: PendingMessage,
    ) -> PoolRequestHandle {
        self.register_waiter(pool, msg, Waiter::Exclusive(Default::default()), true, true)
    }

    /// Returns the write and all read connections of this pool.
    pub fn view_connections(&self) -> (&PoolConnection, &[PoolConnection]) {
        let writer = &self.writes.connection;
        let readers = self.reads.connections.as_slice();

        (writer, readers)
    }

    fn register_waiter(
        &mut self,
        pool: ConnectionPool,
        msg: PendingMessage,
        waiter: Waiter,
        reads: bool,
        writes: bool,
    ) -> PoolRequestHandle {
        let request = Box::new(WaitNode {
            read_entry: None,
            write_entry: None,
            port: msg,
            waiter,
        });
        let request = Box::leak(request);
        let request_completed = self.try_complete(request);
        let request = NonNull::from(request);

        if !request_completed {
            // We couldn't complete the request immediately, add it to relevant queues.
            if reads {
                self.reads.waiters.push(request);
            }

            if writes {
                self.writes.waiters.push(request);
            }
        }

        PoolRequestHandle {
            pool,
            node: request,
        }
    }

    /// Attempts to assign a connection to the given waiter, if one is available.
    ///
    /// Returns whether the node is completed and no longer waiting (in which case this function
    /// would have notified the Dart port). The node can be removed from its queues in that case.
    fn try_complete(&mut self, waiter: &mut WaitNode) -> bool {
        match &mut waiter.waiter {
            Waiter::Reader(reads) => {
                assert!(reads.assigned_connection.is_none());

                if let Some(conn_idx) = self.reads.idle_connections.pop_front() {
                    reads.assigned_connection = Some(conn_idx);
                    waiter.port.send_did_obtain_connection(
                        &self.reads.connections[conn_idx],
                        &self.functions,
                    );
                    return true;
                }

                false
            }
            Waiter::Writer(writes) => {
                assert!(!writes.has_writer);

                if self.try_assign_write(&mut writes.has_writer) {
                    waiter
                        .port
                        .send_did_obtain_connection(&self.writes.connection, &self.functions);
                    return true;
                }

                false
            }
            Waiter::Exclusive(exclusive) => {
                if !self.try_assign_write(&mut exclusive.has_writer) {
                    return false;
                }

                while exclusive.obtained_read_connections < self.reads.connections.len() {
                    let Some(_) = self.reads.idle_connections.pop_front() else {
                        return false;
                    };
                    exclusive.obtained_read_connections += 1;
                }

                waiter.port.send_did_obtain_exclusive(&self.functions);
                true
            }
        }
    }

    fn try_assign_write(&mut self, has_write: &mut bool) -> bool {
        if *has_write {
            true
        } else if !self.writes.acquired {
            self.writes.acquired = true;
            *has_write = true;
            true
        } else {
            false
        }
    }

    fn drop_connection(conn: &mut PoolConnection, functions: &ExternalFunctions) {
        if let Some(cache) = &mut conn.cached_statements {
            cache.close_statements(&functions);
        }

        (functions.sqlite3_close_v2)(conn.raw);
    }

    pub fn register_update_listener(&mut self, update_listener: DartPort) {
        self.update_listeners.push(update_listener);
    }

    pub fn remove_update_listeners(&mut self, removed_listeners: &[DartPort]) {
        self.update_listeners
            .retain(|l| !removed_listeners.contains(l));
    }

    pub fn update_listeners(&self) -> &[DartPort] {
        self.update_listeners.as_slice()
    }

    pub fn register_hooks_on_writer(arc: &ConnectionPool) {
        let mut pool = arc.lock().unwrap();
        let updates_ptr = pool
            .table_updates
            .insert(UnsafeCell::new(CollectedTableUpdates::new(arc)))
            .get();
        let writer = &pool.writes.connection;
        CollectedTableUpdates::attach_to(updates_ptr, &pool.functions, writer.raw);
    }
}

impl Drop for PoolState {
    fn drop(&mut self) {
        // Pool request handles have a reference to the pool and should be dropped first. Still,
        // let's assert we're not about to close a connection that might still be in use.
        assert!(
            !self.writes.acquired,
            "Tried to drop with leased write connection"
        );
        assert_eq!(
            self.reads.idle_connections.len(),
            self.reads.connections.len(),
            "Tried to drop with leased read connection"
        );

        Self::drop_connection(&mut self.writes.connection, &self.functions);
        for read in &mut self.reads.connections {
            Self::drop_connection(read, &self.functions);
        }
    }
}

impl PendingMessage {
    /// Sends a `[tag, true]` message to this port.
    fn send_did_obtain_exclusive(&self, api: &ExternalFunctions) {
        let list_values: &mut [*mut RawDartCObject] = &mut [
            &mut RawDartCObject::from(self.tag),
            &mut RawDartCObject::from(true),
        ];
        let mut array = RawDartCObject {
            type_: RawDartCObject::TYPE_ARRAY,
            value: RawDartCObjectValue {
                as_array: RawDartCObjectArray {
                    length: list_values.len() as isize,
                    values: list_values.as_mut_ptr(),
                },
            },
        };

        (api.dart_post_c_object)(self.port, &mut array);
    }

    /// Sends a `[tag, false, connection_ptr]` message to this port.
    fn send_did_obtain_connection(&self, connection: &PoolConnection, api: &ExternalFunctions) {
        let list_values: &mut [*mut RawDartCObject] = &mut [
            &mut RawDartCObject::from(self.tag),
            &mut RawDartCObject::from(false),
            &mut RawDartCObject::from(connection as *const PoolConnection as i64),
        ];
        let mut array = RawDartCObject {
            type_: RawDartCObject::TYPE_ARRAY,
            value: RawDartCObjectValue {
                as_array: RawDartCObjectArray {
                    length: list_values.len() as isize,
                    values: list_values.as_mut_ptr(),
                },
            },
        };

        (api.dart_post_c_object)(self.port, &mut array);
    }
}

// Trait to extract read_entry or write_entry from a WaitNode struct
trait ExtractEntry {
    fn extract_entry(node: &mut WaitNode) -> &mut Option<QueueEntry>;
}

impl ExtractEntry for ReadState {
    fn extract_entry(node: &mut WaitNode) -> &mut Option<QueueEntry> {
        &mut node.read_entry
    }
}

impl ExtractEntry for WriteState {
    fn extract_entry(node: &mut WaitNode) -> &mut Option<QueueEntry> {
        &mut node.write_entry
    }
}

impl<E: ExtractEntry> Default for LinkedList<E> {
    fn default() -> Self {
        Self {
            first: None,
            last: None,
            _e: PhantomData,
        }
    }
}

impl<E: ExtractEntry> LinkedList<E> {
    fn push(&mut self, mut node: NonNull<WaitNode>) {
        let prev = match self.last {
            None => {
                self.first = Some(node);
                None
            }
            Some(mut last) => {
                E::extract_entry(unsafe { last.as_mut() })
                    .as_mut()
                    .unwrap()
                    .next = Some(node);
                Some(last)
            }
        };

        let slot_on_node = E::extract_entry(unsafe { node.as_mut() });
        debug_assert!(slot_on_node.is_none()); // We're about to insert it...
        *slot_on_node = Some(QueueEntry { prev, next: None });
        self.last = Some(node);
    }

    fn unlink(&mut self, node: &mut WaitNode) {
        let slot = E::extract_entry(node);
        let Some(slot) = slot.take() else {
            panic!("Tried to unlink nonexistent queue entry")
        };

        match slot.prev {
            Some(mut prev) => {
                let prev = unsafe { prev.as_mut() };
                E::extract_entry(prev).as_mut().unwrap().next = slot.next;
            }
            // This was the first node
            None => {
                debug_assert!(slot.prev.is_none());
                self.first = slot.next
            }
        };

        match slot.next {
            Some(mut next) => {
                let next = unsafe { next.as_mut() };
                E::extract_entry(next).as_mut().unwrap().prev = slot.prev;
            }
            // This was the last node
            None => {
                debug_assert!(slot.next.is_none());
                self.last = slot.prev
            }
        }
    }
}

pub struct PoolRequestHandle {
    pool: ConnectionPool,
    node: NonNull<WaitNode>,
}

impl Drop for PoolRequestHandle {
    fn drop(&mut self) {
        let mut pool = self.pool.lock().unwrap();
        unsafe { pool.drop_waiter(self.node) };
    }
}

/// References to `sqlite3` and `Dart_DL` functions we want to use.
///
/// The Dart client will provide these function pointers because we want to link SQLite through
/// hooks instead of adding it as a link-dependency of this crate.
#[derive(Copy, Clone)]
#[repr(C)]
pub struct ExternalFunctions {
    pub sqlite3_update_hook: extern "C" fn(
        Connection,
        Option<extern "C" fn(NonNull<c_void>, c_int, *const c_char, *const c_char, i64)>,
        *mut c_void,
    ) -> *mut c_void,
    pub sqlite3_commit_hook: extern "C" fn(
        Connection,
        Option<extern "C" fn(NonNull<c_void>) -> c_int>,
        *mut c_void,
    ) -> *mut c_void,
    pub sqlite3_rollback_hook: extern "C" fn(
        Connection,
        Option<extern "C" fn(NonNull<c_void>)>,
        *mut c_void,
    ) -> *mut c_void,
    pub sqlite3_finalize: extern "C" fn(PreparedStatement) -> c_int,
    pub sqlite3_close_v2: extern "C" fn(Connection) -> c_int,
    pub dart_post_c_object: extern "C" fn(port: DartPort, message: &mut RawDartCObject) -> bool,
}
