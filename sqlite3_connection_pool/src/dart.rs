use std::ffi::c_int;

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

impl From<bool> for RawDartCObject {
    fn from(value: bool) -> Self {
        Self {
            type_: Dart_CObject_Type_Dart_CObject_kBool,
            value: RawDartCObjectValue { as_bool: value },
        }
    }
}

impl From<i64> for RawDartCObject {
    fn from(value: i64) -> Self {
        Self {
            type_: Dart_CObject_Type_Dart_CObject_kInt64,
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
    //pub as_send_port: _Dart_CObject__bindgen_ty_1__bindgen_ty_1,
    //pub as_capability: _Dart_CObject__bindgen_ty_1__bindgen_ty_2,
    pub as_array: RawDartCObjectArray,
    //pub as_typed_data: _Dart_CObject__bindgen_ty_1__bindgen_ty_4,
    //pub as_external_typed_data: _Dart_CObject__bindgen_ty_1__bindgen_ty_5,
    //pub as_native_pointer: _Dart_CObject__bindgen_ty_1__bindgen_ty_6,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectArray {
    pub length: isize,
    pub values: *mut *mut RawDartCObject,
}

pub const Dart_CObject_Type_Dart_CObject_kNull: c_int = 0;
pub const Dart_CObject_Type_Dart_CObject_kBool: c_int = 1;
pub const Dart_CObject_Type_Dart_CObject_kInt64: c_int = 3;
pub const Dart_CObject_Type_Dart_CObject_kString: c_int = 5;
pub const Dart_CObject_Type_Dart_CObject_kArray: c_int = 6;
