use std::ffi::c_int;

mod sqlite3;

#[no_mangle]
pub extern "C" fn sqlite3_os_init() -> c_int {
    return sqlite3::SQLITE_OK as c_int;
}

#[no_mangle]
pub extern "C" fn sqlite3_os_end() -> c_int {
    return sqlite3::SQLITE_OK as c_int;
}
