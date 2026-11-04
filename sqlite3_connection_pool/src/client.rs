use crate::dart::DartPort;
use crate::pool::ConnectionPool;

pub struct PoolClient {
    pub pool: ConnectionPool,
    update_listeners: Vec<DartPort>,
}

impl PoolClient {
    pub fn new(pool: ConnectionPool) -> Self {
        Self {
            pool,
            update_listeners: Default::default(),
        }
    }

    pub fn register_update_listener(&mut self, update_listener: DartPort) {
        self.update_listeners.push(update_listener);
        let mut pool = self.pool.lock().unwrap();
        pool.register_update_listener(update_listener);
    }

    pub fn remove_update_listener(&mut self, update_listener: DartPort) {
        self.update_listeners
            .retain(|listener| listener != &update_listener);
        let mut pool = self.pool.lock().unwrap();
        pool.remove_update_listeners(&[update_listener]);
    }
}

impl Drop for PoolClient {
    fn drop(&mut self) {
        if !self.update_listeners.is_empty() {
            let mut pool = self.pool.lock().unwrap();
            pool.remove_update_listeners(&self.update_listeners);
        }
    }
}
