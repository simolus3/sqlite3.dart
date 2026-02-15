use std::ffi::c_void;

#[derive(Copy, Clone)]
#[repr(transparent)]
pub struct Connection(pub *const c_void);

unsafe impl Send for Connection {}
unsafe impl Sync for Connection {}
