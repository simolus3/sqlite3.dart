#![no_std]
extern crate alloc;

use core::alloc::{GlobalAlloc, Layout};
use core::ffi::c_int;

use alloc::ffi::CString;
use alloc::string::ToString;
use common::{sqlite3_auto_extension, sqlite3_free, sqlite3_malloc};
use extension::signal_fts5_tokenizer_init;
use wasm::dartLogError;

mod common;
mod extension;
mod tokenize;

#[no_mangle]
pub extern "C" fn sqlite3_os_init() -> c_int {
    // This would be a good place to set up extensions.
    unsafe { sqlite3_auto_extension(signal_fts5_tokenizer_init) };

    return 0;
}

#[no_mangle]
pub extern "C" fn sqlite3_os_end() -> c_int {
    return 0;
}

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    let msg = info.to_string();
    let c_msg = unsafe { CString::new(msg).unwrap_unchecked() };

    unsafe {
        dartLogError(c_msg.as_ptr());
    }

    loop {}
}

struct SQLite3Allocator;

#[global_allocator]
static ALLOCATOR: SQLite3Allocator = SQLite3Allocator;

unsafe impl GlobalAlloc for SQLite3Allocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        sqlite3_malloc(layout.size() as c_int).cast()
    }

    unsafe fn dealloc(&self, ptr: *mut u8, _layout: Layout) {
        sqlite3_free(ptr as *mut core::ffi::c_void);
    }
}

mod wasm {
    use core::ffi::c_char;

    #[link(wasm_import_module = "dart")]
    extern "C" {
        #[link_name = "error_log"]
        pub fn dartLogError(msg: *const c_char);
    }
}
