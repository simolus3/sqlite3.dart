use std::{
    ffi::{CStr, c_char, c_int, c_void},
    mem,
};

/// A wrapper around a native `SendPort`.
#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(transparent)]
pub struct DartPort(i64);

// https://github.com/dart-lang/sdk/blob/0a88f4ef734c464150b253708bb2699be3598c65/runtime/include/dart_native_api.h#L43-L100

#[repr(C)]
pub struct RawDartCObject {
    pub type_: c_int,
    pub value: RawDartCObjectValue,
}

impl RawDartCObject {
    pub const TYPE_BOOL: c_int = 1;
    pub const TYPE_INT64: c_int = 3;
    pub const TYPE_STRING: c_int = 5;
    pub const TYPE_ARRAY: c_int = 6;
}

impl From<bool> for RawDartCObject {
    fn from(value: bool) -> Self {
        Self {
            type_: Self::TYPE_BOOL,
            value: RawDartCObjectValue { as_bool: value },
        }
    }
}

impl From<i64> for RawDartCObject {
    fn from(value: i64) -> Self {
        Self {
            type_: Self::TYPE_INT64,
            value: RawDartCObjectValue { as_int64: value },
        }
    }
}

#[repr(C)]
pub union RawDartCObjectValue {
    pub as_bool: bool,
    pub as_int32: i32,
    pub as_int64: i64,
    pub as_double: f64,
    pub as_string: *const ::core::ffi::c_char,
    pub as_send_port: RawDartCObjectSendPort,
    pub as_capability: RawDartCObjectCapability,
    pub as_array: RawDartCObjectArray,
    pub as_typed_data: RawDartCObjectTypedData,
    pub as_external_typed_data: RawDartCObjectExternalTypedData,
    pub as_native_pointer: RawDartCObjectNativePointer,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectSendPort {
    pub id: DartPort,
    pub origin_id: DartPort,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectCapability {
    pub id: i64,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectArray {
    pub length: isize,
    pub values: *mut *mut RawDartCObject,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectTypedData {
    pub type_: c_int,
    pub length: isize,
    pub values: *const u8,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectExternalTypedData {
    pub type_: c_int,
    pub length: isize,
    pub data: *mut u8,
    pub peer: *mut c_void,
    pub callback: *mut c_void,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectNativePointer {
    pub ptr: isize,
    pub size: isize,
    pub callback: *mut c_void,
}

#[repr(transparent)]
pub struct Handle(pub *const c_void);

#[repr(transparent)]
pub struct FinalizableHandle(pub *const c_void);

pub type PostCObject = extern "C" fn(port: DartPort, message: &mut RawDartCObject) -> bool;

pub type HandleFinalizer = extern "C" fn(isolate_callback_data: *mut c_void, peer: *mut c_void);

pub type NewFinalizableHandle = extern "C" fn(
    handle: Handle,
    peer: *const c_void,
    external_allocation_size: isize,
    callback: HandleFinalizer,
) -> FinalizableHandle;

// https://github.com/dart-lang/sdk/blob/main/runtime/include/internal/dart_api_dl_impl.h
#[repr(C)]
struct ApiEntry {
    name: *const c_char,
    function: *const c_void,
}

#[repr(C)]
struct DartApi {
    major: c_int,
    minor: c_int,
    functions: *const ApiEntry,
}

/// Function pointers to Dart VM APIs, provided from `dart:ffi`.
#[derive(Clone, Copy)]
pub struct Functions {
    /// Posts a structure to a `SendPort` in Dart.
    ///
    /// [API definition](https://github.com/dart-lang/sdk/blob/576c9cc4b132e7ccf6de1799bcc7199c3b8313e9/runtime/include/dart_native_api.h#L106-L129)
    pub post_c_object: PostCObject,
    /// Invokes a callback once a Dart object is GCed. The object can be shared across isolates, the
    /// callback runs once it's no longer reachable on any isolate in the group (or once the group
    /// shuts down).
    ///
    /// [API definition](https://github.com/dart-lang/sdk/blob/576c9cc4b132e7ccf6de1799bcc7199c3b8313e9/runtime/include/dart_api.h#L507-L545).
    pub new_finalizable_handle: NewFinalizableHandle,
}

impl Functions {
    pub unsafe fn initialize(ptr: *const c_void) -> Result<Self, FunctionError> {
        // Ported from https://github.com/dart-lang/sdk/blob/main/runtime/include/dart_api_dl.c
        let symbols = unsafe { (ptr as *const DartApi).as_ref_unchecked() };
        // Minor versions only add new symbols and we check for them being present, so we only need
        // to compare major versions.
        if symbols.major != Self::DART_API_DL_MAJOR_VERSION {
            return Err(FunctionError::InvalidMajorVersion);
        }

        let mut post_c_object = None::<PostCObject>;
        let mut new_finalizable_handle = None::<NewFinalizableHandle>;

        let mut entry_ptr = symbols.functions;
        loop {
            let entry = unsafe { entry_ptr.as_ref_unchecked() };
            if entry.name.is_null() {
                break Err(FunctionError::MissingSymbol);
            }

            let name = unsafe { CStr::from_ptr(entry.name) };
            if name == Self::NAME_POST_C_OBJECT {
                post_c_object = Some(unsafe { mem::transmute(entry.function) });
            } else if name == Self::NAME_NEW_FINALIZABLE_HANDLE {
                new_finalizable_handle = Some(unsafe { mem::transmute(entry.function) });
            }

            if let (Some(post_c_object), Some(new_finalizable_handle)) =
                (post_c_object, new_finalizable_handle)
            {
                return Ok(Self {
                    post_c_object,
                    new_finalizable_handle,
                });
            };

            entry_ptr = unsafe { entry_ptr.add(1) };
        }
    }

    const DART_API_DL_MAJOR_VERSION: c_int = 2;

    const NAME_POST_C_OBJECT: &'static CStr = c"Dart_PostCObject";
    const NAME_NEW_FINALIZABLE_HANDLE: &'static CStr = c"Dart_NewFinalizableHandle";
}

#[derive(Debug)]
pub enum FunctionError {
    InvalidMajorVersion,
    MissingSymbol,
}
