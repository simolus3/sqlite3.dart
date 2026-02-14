use crate::connection::Connection;
use crate::dart::{DartPort, RawDartCObject, RawDartCObjectArray, RawDartCObjectValue};
use std::collections::VecDeque;
use std::ffi::c_int;
use std::marker::PhantomData;
use std::ptr::NonNull;
use std::sync::{Arc, Mutex};

/// A connection pool can be locked, in which case some Dart actor has exclusive access to all
/// connections. When a new pool is initialized, it is also in this state.
pub type ConnectionPool = Arc<Mutex<PoolState>>;

pub struct PoolState {
    reads: ReadState,
    writes: WriteState,
    functions: ExternalFunctions,
}

struct ReadState {
    connections: Vec<Connection>,
    idle_connections: VecDeque<usize>,
    waiters: LinkedList<Self>,
}

struct WriteState {
    connection: Connection,
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

struct WaitNode {
    read_entry: Option<QueueEntry>,
    write_entry: Option<QueueEntry>,

    port: PendingMessage,
    waiter: Waiter,
}

unsafe impl Send for WaitNode {}
unsafe impl Sync for WaitNode {}

pub struct PendingMessage {
    pub tag: i64,
    pub port: DartPort,
}

struct QueueEntry {
    prev: Option<NonNull<WaitNode>>,
    next: Option<NonNull<WaitNode>>,
}

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
    pub fn new(functions: ExternalFunctions, writer: Connection, reads: &[Connection]) -> Self {
        Self {
            reads: ReadState {
                idle_connections: (0usize..reads.len()).collect(),
                connections: reads.into(),
                waiters: Default::default(),
            },
            writes: WriteState {
                connection: writer,
                acquired: false,
                waiters: Default::default(),
            },
            functions,
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

    pub fn view_connections(&self) -> (&Connection, &[Connection]) {
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

    fn try_complete(&mut self, waiter: &mut WaitNode) -> bool {
        match &mut waiter.waiter {
            Waiter::Reader(reads) => {
                assert!(reads.assigned_connection.is_none());

                if let Some(conn_idx) = self.reads.idle_connections.pop_front() {
                    reads.assigned_connection = Some(conn_idx);
                    waiter.port.send_did_obtain_connection(
                        self.reads.connections[conn_idx],
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
                        .send_did_obtain_connection(self.writes.connection, &self.functions);
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

    fn drop_connection(&self, conn: Connection) {
        (self.functions.sqlite3_close_v2)(conn);
    }
}

impl Drop for PoolState {
    fn drop(&mut self) {
        assert!(
            !self.writes.acquired,
            "Tried to drop with leased write connection"
        );
        assert_eq!(
            self.reads.idle_connections.len(),
            self.reads.connections.len(),
            "Tried to drop with leased read connection"
        );

        self.drop_connection(self.writes.connection);
        for read in &self.reads.connections {
            self.drop_connection(*read)
        }
    }
}

impl PendingMessage {
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

    fn send_did_obtain_connection(&self, connection: Connection, api: &ExternalFunctions) {
        let list_values: &mut [*mut RawDartCObject] = &mut [
            &mut RawDartCObject::from(self.tag),
            &mut RawDartCObject::from(false),
            &mut RawDartCObject::from(connection.0 as i64),
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

        let x = (api.dart_post_c_object)(self.port, &mut array);
        if !x {
            panic!("todo: failed isolate message post")
        }
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
        debug_assert!(slot_on_node.is_none());
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
            None => self.first = slot.next,
        };

        match slot.next {
            Some(mut next) => {
                let next = unsafe { next.as_mut() };
                E::extract_entry(next).as_mut().unwrap().prev = slot.prev;
            }
            // This was the last node
            None => self.last = slot.prev,
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
    pub sqlite3_close_v2: extern "C" fn(Connection) -> c_int,
    pub dart_post_c_object: extern "C" fn(port: DartPort, message: *mut RawDartCObject) -> bool,
}
