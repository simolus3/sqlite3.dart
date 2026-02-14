use std::ffi::{c_int, c_void};

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