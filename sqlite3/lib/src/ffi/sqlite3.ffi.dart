// auto-generated, DO NOT EDIT
// Instead, run pub run build_runner build

import 'dart:ffi';

class char extends Opaque {}

class sqlite3 extends Opaque {}

class sqlite3_stmt extends Opaque {}

class sqlite3_value extends Opaque {}

class sqlite3_context extends Opaque {}

typedef _sqlite3_open_v2_native = Int32 Function(
    Pointer<char>, Pointer<Pointer<sqlite3>>, Int32, Pointer<char>);
typedef sqlite3_open_v2_dart = int Function(Pointer<char> filename,
    Pointer<Pointer<sqlite3>> ppDb, int flags, Pointer<char> zVfs);
typedef _sqlite3_close_v2_native = Int32 Function(Pointer<sqlite3>);
typedef sqlite3_close_v2_dart = int Function(Pointer<sqlite3> db);
typedef _sqlite3_extended_result_codes_native = Int32 Function(
    Pointer<sqlite3>, Int32);
typedef sqlite3_extended_result_codes_dart = int Function(
    Pointer<sqlite3> db, int onoff);
typedef _sqlite3_extended_errcode_native = Int32 Function(Pointer<sqlite3>);
typedef sqlite3_extended_errcode_dart = int Function(Pointer<sqlite3> db);
typedef _sqlite3_errmsg_native = Pointer<char> Function(Pointer<sqlite3>);
typedef sqlite3_errmsg_dart = Pointer<char> Function(Pointer<sqlite3> db);
typedef _sqlite3_errstr_native = Pointer<char> Function(Int32);
typedef sqlite3_errstr_dart = Pointer<char> Function(int code);
typedef _sqlite3_free_native = Void Function(Pointer<Void>);
typedef sqlite3_free_dart = void Function(Pointer<Void> ptr);
typedef _sqlite3_libversion_native = Pointer<char> Function();
typedef sqlite3_libversion_dart = Pointer<char> Function();
typedef _sqlite3_sourceid_native = Pointer<char> Function();
typedef sqlite3_sourceid_dart = Pointer<char> Function();
typedef _sqlite3_libversion_number_native = Int32 Function();
typedef sqlite3_libversion_number_dart = int Function();
typedef _sqlite3_last_insert_rowid_native = Int64 Function(Pointer<sqlite3>);
typedef sqlite3_last_insert_rowid_dart = int Function(Pointer<sqlite3> db);
typedef _sqlite3_changes_native = Int32 Function(Pointer<sqlite3>);
typedef sqlite3_changes_dart = int Function(Pointer<sqlite3> db);
typedef _sqlite3_exec_native = Int32 Function(Pointer<sqlite3>, Pointer<char>,
    Pointer<Void>, Pointer<Void>, Pointer<Pointer<char>>);
typedef sqlite3_exec_dart = int Function(
    Pointer<sqlite3> db,
    Pointer<char> sql,
    Pointer<Void> callback,
    Pointer<Void> argToCb,
    Pointer<Pointer<char>> errorOut);
typedef _sqlite3_finalize_native = Int32 Function(Pointer<sqlite3_stmt>);
typedef sqlite3_finalize_dart = int Function(Pointer<sqlite3_stmt> pStmt);
typedef _sqlite3_step_native = Int32 Function(Pointer<sqlite3_stmt>);
typedef sqlite3_step_dart = int Function(Pointer<sqlite3_stmt> pStmt);
typedef _sqlite3_reset_native = Int32 Function(Pointer<sqlite3_stmt>);
typedef sqlite3_reset_dart = int Function(Pointer<sqlite3_stmt> pStmt);
typedef _sqlite3_column_count_native = Int32 Function(Pointer<sqlite3_stmt>);
typedef sqlite3_column_count_dart = int Function(Pointer<sqlite3_stmt> pStmt);
typedef _sqlite3_bind_parameter_count_native = Int32 Function(
    Pointer<sqlite3_stmt>);
typedef sqlite3_bind_parameter_count_dart = int Function(
    Pointer<sqlite3_stmt> pStmt);
typedef _sqlite3_column_name_native = Pointer<char> Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_name_dart = Pointer<char> Function(
    Pointer<sqlite3_stmt> pStmt, int N);
typedef _sqlite3_bind_blob64_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32, Pointer<Void>, Uint64, Pointer<Void>);
typedef sqlite3_bind_blob64_dart = int Function(Pointer<sqlite3_stmt> pStmt,
    int index, Pointer<Void> data, int length, Pointer<Void> destructor);
typedef _sqlite3_bind_double_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32, Double);
typedef sqlite3_bind_double_dart = int Function(
    Pointer<sqlite3_stmt> pStmt, int index, double data);
typedef _sqlite3_bind_int64_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32, Int64);
typedef sqlite3_bind_int64_dart = int Function(
    Pointer<sqlite3_stmt> pStmt, int index, int data);
typedef _sqlite3_bind_null_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_bind_null_dart = int Function(
    Pointer<sqlite3_stmt> pStmt, int index);
typedef _sqlite3_bind_text_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32, Pointer<char>, Int32, Pointer<Void>);
typedef sqlite3_bind_text_dart = int Function(Pointer<sqlite3_stmt> pStmt,
    int index, Pointer<char> data, int length, Pointer<Void> destructor);
typedef _sqlite3_column_blob_native = Pointer<Void> Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_blob_dart = Pointer<Void> Function(
    Pointer<sqlite3_stmt> pStmt, int iCol);
typedef _sqlite3_column_double_native = Double Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_double_dart = double Function(
    Pointer<sqlite3_stmt> pStmt, int iCol);
typedef _sqlite3_column_int64_native = Int64 Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_int64_dart = int Function(
    Pointer<sqlite3_stmt> pStmt, int iCol);
typedef _sqlite3_column_text_native = Pointer<char> Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_text_dart = Pointer<char> Function(
    Pointer<sqlite3_stmt> pStmt, int iCol);
typedef _sqlite3_column_bytes_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_bytes_dart = int Function(
    Pointer<sqlite3_stmt> pStmt, int iCol);
typedef _sqlite3_column_type_native = Int32 Function(
    Pointer<sqlite3_stmt>, Int32);
typedef sqlite3_column_type_dart = int Function(
    Pointer<sqlite3_stmt> pStmt, int iCol);
typedef _sqlite3_value_blob_native = Pointer<Void> Function(
    Pointer<sqlite3_value>);
typedef sqlite3_value_blob_dart = Pointer<Void> Function(
    Pointer<sqlite3_value> value);
typedef _sqlite3_value_double_native = Double Function(Pointer<sqlite3_value>);
typedef sqlite3_value_double_dart = double Function(
    Pointer<sqlite3_value> value);
typedef _sqlite3_value_type_native = Int32 Function(Pointer<sqlite3_value>);
typedef sqlite3_value_type_dart = int Function(Pointer<sqlite3_value> value);
typedef _sqlite3_value_int64_native = Int64 Function(Pointer<sqlite3_value>);
typedef sqlite3_value_int64_dart = int Function(Pointer<sqlite3_value> value);
typedef _sqlite3_value_text_native = Pointer<char> Function(
    Pointer<sqlite3_value>);
typedef sqlite3_value_text_dart = Pointer<char> Function(
    Pointer<sqlite3_value> value);
typedef _sqlite3_value_bytes_native = Int32 Function(Pointer<sqlite3_value>);
typedef sqlite3_value_bytes_dart = int Function(Pointer<sqlite3_value> value);
typedef _sqlite3_create_function_v2_native = Int32 Function(
    Pointer<sqlite3>,
    Pointer<char>,
    Int32,
    Int32,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>);
typedef sqlite3_create_function_v2_dart = int Function(
    Pointer<sqlite3> db,
    Pointer<char> zFunctionName,
    int nArg,
    int eTextRep,
    Pointer<Void> pApp,
    Pointer<Void> xFunc,
    Pointer<Void> xStep,
    Pointer<Void> xFinal,
    Pointer<Void> xDestroy);
typedef _sqlite3_aggregate_context_native = Pointer<Void> Function(
    Pointer<sqlite3_context>, Int32);
typedef sqlite3_aggregate_context_dart = Pointer<Void> Function(
    Pointer<sqlite3_context> ctx, int nBytes);
typedef _sqlite3_user_data_native = Pointer<Void> Function(
    Pointer<sqlite3_context>);
typedef sqlite3_user_data_dart = Pointer<Void> Function(
    Pointer<sqlite3_context> ctx);
typedef _sqlite3_result_blob64_native = Void Function(
    Pointer<sqlite3_context>, Pointer<Void>, Uint64, Pointer<Void>);
typedef sqlite3_result_blob64_dart = void Function(Pointer<sqlite3_context> ctx,
    Pointer<Void> data, int length, Pointer<Void> destructor);
typedef _sqlite3_result_double_native = Void Function(
    Pointer<sqlite3_context>, Double);
typedef sqlite3_result_double_dart = void Function(
    Pointer<sqlite3_context> ctx, double result);
typedef _sqlite3_result_error_native = Void Function(
    Pointer<sqlite3_context>, Pointer<char>, Int32);
typedef sqlite3_result_error_dart = void Function(
    Pointer<sqlite3_context> ctx, Pointer<char> msg, int length);
typedef _sqlite3_result_int64_native = Void Function(
    Pointer<sqlite3_context>, Int64);
typedef sqlite3_result_int64_dart = void Function(
    Pointer<sqlite3_context> ctx, int result);
typedef _sqlite3_result_null_native = Void Function(Pointer<sqlite3_context>);
typedef sqlite3_result_null_dart = void Function(Pointer<sqlite3_context> ctx);
typedef _sqlite3_result_text_native = Void Function(
    Pointer<sqlite3_context>, Pointer<char>, Int32, Pointer<Void>);
typedef sqlite3_result_text_dart = void Function(Pointer<sqlite3_context> ctx,
    Pointer<char> data, int length, Pointer<Void> destructor);

class Bindings {
  final DynamicLibrary library;
  final sqlite3_open_v2_dart sqlite3_open_v2;
  final sqlite3_close_v2_dart sqlite3_close_v2;
  final sqlite3_extended_result_codes_dart sqlite3_extended_result_codes;
  final sqlite3_extended_errcode_dart sqlite3_extended_errcode;
  final sqlite3_errmsg_dart sqlite3_errmsg;
  final sqlite3_errstr_dart sqlite3_errstr;
  final sqlite3_free_dart sqlite3_free;
  final sqlite3_libversion_dart sqlite3_libversion;
  final sqlite3_sourceid_dart sqlite3_sourceid;
  final sqlite3_libversion_number_dart sqlite3_libversion_number;
  final sqlite3_last_insert_rowid_dart sqlite3_last_insert_rowid;
  final sqlite3_changes_dart sqlite3_changes;
  final sqlite3_exec_dart sqlite3_exec;
  final sqlite3_finalize_dart sqlite3_finalize;
  final sqlite3_step_dart sqlite3_step;
  final sqlite3_reset_dart sqlite3_reset;
  final sqlite3_column_count_dart sqlite3_column_count;
  final sqlite3_bind_parameter_count_dart sqlite3_bind_parameter_count;
  final sqlite3_column_name_dart sqlite3_column_name;
  final sqlite3_bind_blob64_dart sqlite3_bind_blob64;
  final sqlite3_bind_double_dart sqlite3_bind_double;
  final sqlite3_bind_int64_dart sqlite3_bind_int64;
  final sqlite3_bind_null_dart sqlite3_bind_null;
  final sqlite3_bind_text_dart sqlite3_bind_text;
  final sqlite3_column_blob_dart sqlite3_column_blob;
  final sqlite3_column_double_dart sqlite3_column_double;
  final sqlite3_column_int64_dart sqlite3_column_int64;
  final sqlite3_column_text_dart sqlite3_column_text;
  final sqlite3_column_bytes_dart sqlite3_column_bytes;
  final sqlite3_column_type_dart sqlite3_column_type;
  final sqlite3_value_blob_dart sqlite3_value_blob;
  final sqlite3_value_double_dart sqlite3_value_double;
  final sqlite3_value_type_dart sqlite3_value_type;
  final sqlite3_value_int64_dart sqlite3_value_int64;
  final sqlite3_value_text_dart sqlite3_value_text;
  final sqlite3_value_bytes_dart sqlite3_value_bytes;
  final sqlite3_create_function_v2_dart sqlite3_create_function_v2;
  final sqlite3_aggregate_context_dart sqlite3_aggregate_context;
  final sqlite3_user_data_dart sqlite3_user_data;
  final sqlite3_result_blob64_dart sqlite3_result_blob64;
  final sqlite3_result_double_dart sqlite3_result_double;
  final sqlite3_result_error_dart sqlite3_result_error;
  final sqlite3_result_int64_dart sqlite3_result_int64;
  final sqlite3_result_null_dart sqlite3_result_null;
  final sqlite3_result_text_dart sqlite3_result_text;
  Bindings(this.library)
      : sqlite3_open_v2 = library.lookupFunction<_sqlite3_open_v2_native,
            sqlite3_open_v2_dart>('sqlite3_open_v2'),
        sqlite3_close_v2 = library.lookupFunction<_sqlite3_close_v2_native,
            sqlite3_close_v2_dart>('sqlite3_close_v2'),
        sqlite3_extended_result_codes = library.lookupFunction<
                _sqlite3_extended_result_codes_native,
                sqlite3_extended_result_codes_dart>(
            'sqlite3_extended_result_codes'),
        sqlite3_extended_errcode = library.lookupFunction<
            _sqlite3_extended_errcode_native,
            sqlite3_extended_errcode_dart>('sqlite3_extended_errcode'),
        sqlite3_errmsg =
            library.lookupFunction<_sqlite3_errmsg_native, sqlite3_errmsg_dart>(
                'sqlite3_errmsg'),
        sqlite3_errstr =
            library.lookupFunction<_sqlite3_errstr_native, sqlite3_errstr_dart>(
                'sqlite3_errstr'),
        sqlite3_free =
            library.lookupFunction<_sqlite3_free_native, sqlite3_free_dart>(
                'sqlite3_free'),
        sqlite3_libversion = library.lookupFunction<_sqlite3_libversion_native,
            sqlite3_libversion_dart>('sqlite3_libversion'),
        sqlite3_sourceid = library.lookupFunction<_sqlite3_sourceid_native,
            sqlite3_sourceid_dart>('sqlite3_sourceid'),
        sqlite3_libversion_number = library.lookupFunction<
            _sqlite3_libversion_number_native,
            sqlite3_libversion_number_dart>('sqlite3_libversion_number'),
        sqlite3_last_insert_rowid = library.lookupFunction<
            _sqlite3_last_insert_rowid_native,
            sqlite3_last_insert_rowid_dart>('sqlite3_last_insert_rowid'),
        sqlite3_changes = library.lookupFunction<_sqlite3_changes_native,
            sqlite3_changes_dart>('sqlite3_changes'),
        sqlite3_exec =
            library.lookupFunction<_sqlite3_exec_native, sqlite3_exec_dart>(
                'sqlite3_exec'),
        sqlite3_finalize = library.lookupFunction<_sqlite3_finalize_native,
            sqlite3_finalize_dart>('sqlite3_finalize'),
        sqlite3_step =
            library.lookupFunction<_sqlite3_step_native, sqlite3_step_dart>(
                'sqlite3_step'),
        sqlite3_reset =
            library.lookupFunction<_sqlite3_reset_native, sqlite3_reset_dart>(
                'sqlite3_reset'),
        sqlite3_column_count = library.lookupFunction<
            _sqlite3_column_count_native,
            sqlite3_column_count_dart>('sqlite3_column_count'),
        sqlite3_bind_parameter_count = library.lookupFunction<
            _sqlite3_bind_parameter_count_native,
            sqlite3_bind_parameter_count_dart>('sqlite3_bind_parameter_count'),
        sqlite3_column_name = library.lookupFunction<
            _sqlite3_column_name_native,
            sqlite3_column_name_dart>('sqlite3_column_name'),
        sqlite3_bind_blob64 = library.lookupFunction<
            _sqlite3_bind_blob64_native,
            sqlite3_bind_blob64_dart>('sqlite3_bind_blob64'),
        sqlite3_bind_double = library.lookupFunction<
            _sqlite3_bind_double_native,
            sqlite3_bind_double_dart>('sqlite3_bind_double'),
        sqlite3_bind_int64 = library.lookupFunction<_sqlite3_bind_int64_native,
            sqlite3_bind_int64_dart>('sqlite3_bind_int64'),
        sqlite3_bind_null = library.lookupFunction<_sqlite3_bind_null_native,
            sqlite3_bind_null_dart>('sqlite3_bind_null'),
        sqlite3_bind_text = library.lookupFunction<_sqlite3_bind_text_native,
            sqlite3_bind_text_dart>('sqlite3_bind_text'),
        sqlite3_column_blob = library.lookupFunction<
            _sqlite3_column_blob_native,
            sqlite3_column_blob_dart>('sqlite3_column_blob'),
        sqlite3_column_double = library.lookupFunction<
            _sqlite3_column_double_native,
            sqlite3_column_double_dart>('sqlite3_column_double'),
        sqlite3_column_int64 = library.lookupFunction<
            _sqlite3_column_int64_native,
            sqlite3_column_int64_dart>('sqlite3_column_int64'),
        sqlite3_column_text = library.lookupFunction<
            _sqlite3_column_text_native,
            sqlite3_column_text_dart>('sqlite3_column_text'),
        sqlite3_column_bytes = library.lookupFunction<
            _sqlite3_column_bytes_native,
            sqlite3_column_bytes_dart>('sqlite3_column_bytes'),
        sqlite3_column_type = library.lookupFunction<
            _sqlite3_column_type_native,
            sqlite3_column_type_dart>('sqlite3_column_type'),
        sqlite3_value_blob = library.lookupFunction<_sqlite3_value_blob_native,
            sqlite3_value_blob_dart>('sqlite3_value_blob'),
        sqlite3_value_double = library.lookupFunction<
            _sqlite3_value_double_native,
            sqlite3_value_double_dart>('sqlite3_value_double'),
        sqlite3_value_type = library.lookupFunction<_sqlite3_value_type_native,
            sqlite3_value_type_dart>('sqlite3_value_type'),
        sqlite3_value_int64 = library.lookupFunction<
            _sqlite3_value_int64_native,
            sqlite3_value_int64_dart>('sqlite3_value_int64'),
        sqlite3_value_text = library.lookupFunction<_sqlite3_value_text_native,
            sqlite3_value_text_dart>('sqlite3_value_text'),
        sqlite3_value_bytes = library.lookupFunction<
            _sqlite3_value_bytes_native,
            sqlite3_value_bytes_dart>('sqlite3_value_bytes'),
        sqlite3_create_function_v2 = library.lookupFunction<
            _sqlite3_create_function_v2_native,
            sqlite3_create_function_v2_dart>('sqlite3_create_function_v2'),
        sqlite3_aggregate_context = library.lookupFunction<
            _sqlite3_aggregate_context_native,
            sqlite3_aggregate_context_dart>('sqlite3_aggregate_context'),
        sqlite3_user_data = library.lookupFunction<_sqlite3_user_data_native,
            sqlite3_user_data_dart>('sqlite3_user_data'),
        sqlite3_result_blob64 = library.lookupFunction<
            _sqlite3_result_blob64_native,
            sqlite3_result_blob64_dart>('sqlite3_result_blob64'),
        sqlite3_result_double = library.lookupFunction<
            _sqlite3_result_double_native,
            sqlite3_result_double_dart>('sqlite3_result_double'),
        sqlite3_result_error = library.lookupFunction<
            _sqlite3_result_error_native,
            sqlite3_result_error_dart>('sqlite3_result_error'),
        sqlite3_result_int64 = library.lookupFunction<
            _sqlite3_result_int64_native,
            sqlite3_result_int64_dart>('sqlite3_result_int64'),
        sqlite3_result_null = library.lookupFunction<
            _sqlite3_result_null_native,
            sqlite3_result_null_dart>('sqlite3_result_null'),
        sqlite3_result_text = library.lookupFunction<
            _sqlite3_result_text_native,
            sqlite3_result_text_dart>('sqlite3_result_text');
}
