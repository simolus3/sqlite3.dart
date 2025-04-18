// ignore_for_file: type=lint
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
@ffi.DefaultAsset('package:sqlite3_native_assets/sqlite3_native_assets.dart')
library;

import 'dart:ffi' as ffi;
import 'shared.dart' as imp$1;
import '' as self;

@ffi.Native<ffi.Pointer<imp$1.sqlite3_char>>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_temp_directory;

@ffi.Native<ffi.Int Function()>()
external int sqlite3_initialize();

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>()
external void sqlite3_free(
  ffi.Pointer<ffi.Void> arg0,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3>>,
        ffi.Int,
        ffi.Pointer<imp$1.sqlite3_char>)>()
external int sqlite3_open_v2(
  ffi.Pointer<imp$1.sqlite3_char> filename,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3>> ppDb,
  int flags,
  ffi.Pointer<imp$1.sqlite3_char> zVfs,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3>)>()
external int sqlite3_close_v2(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_char> Function(
        ffi.Pointer<imp$1.sqlite3>, ffi.Pointer<imp$1.sqlite3_char>)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_db_filename(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> zDbName,
);

@ffi.Native<ffi.Pointer<imp$1.sqlite3_char> Function(ffi.Int)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_compileoption_get(
  int N,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3>, ffi.Int)>()
external int sqlite3_extended_result_codes(
  ffi.Pointer<imp$1.sqlite3> db,
  int onoff,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3>)>()
external int sqlite3_extended_errcode(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_char> Function(ffi.Pointer<imp$1.sqlite3>)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_errmsg(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<ffi.Pointer<imp$1.sqlite3_char> Function(ffi.Int)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_errstr(
  int code,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3>)>()
external int sqlite3_error_offset(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<ffi.Pointer<imp$1.sqlite3_char> Function()>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_libversion();

@ffi.Native<ffi.Pointer<imp$1.sqlite3_char> Function()>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_sourceid();

@ffi.Native<ffi.Int Function()>()
external int sqlite3_libversion_number();

@ffi.Native<ffi.Int64 Function(ffi.Pointer<imp$1.sqlite3>)>()
external int sqlite3_last_insert_rowid(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3>)>()
external int sqlite3_changes(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>>)>()
external int sqlite3_exec(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> sql,
  ffi.Pointer<ffi.Void> callback,
  ffi.Pointer<ffi.Void> argToCb,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>> errorOut,
);

@ffi.Native<
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(
                    ffi.Pointer<ffi.Void>,
                    ffi.Int,
                    ffi.Pointer<imp$1.sqlite3_char>,
                    ffi.Pointer<imp$1.sqlite3_char>,
                    ffi.Int64)>>,
        ffi.Pointer<ffi.Void>)>()
external ffi.Pointer<ffi.Void> sqlite3_update_hook(
  ffi.Pointer<imp$1.sqlite3> arg0,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Int,
                  ffi.Pointer<imp$1.sqlite3_char>,
                  ffi.Pointer<imp$1.sqlite3_char>,
                  ffi.Int64)>>
      arg1,
  ffi.Pointer<ffi.Void> arg2,
);

@ffi.Native<
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<
            ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.Void>)>>,
        ffi.Pointer<ffi.Void>)>()
external ffi.Pointer<ffi.Void> sqlite3_commit_hook(
  ffi.Pointer<imp$1.sqlite3> arg0,
  ffi.Pointer<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.Void>)>> arg1,
  ffi.Pointer<ffi.Void> arg2,
);

@ffi.Native<
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<
            ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>,
        ffi.Pointer<ffi.Void>)>()
external ffi.Pointer<ffi.Void> sqlite3_rollback_hook(
  ffi.Pointer<imp$1.sqlite3> arg0,
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
      arg1,
  ffi.Pointer<ffi.Void> arg2,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3>)>()
external int sqlite3_get_autocommit(
  ffi.Pointer<imp$1.sqlite3> db,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Int,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_stmt>>,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>>)>()
external int sqlite3_prepare_v2(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> zSql,
  int nByte,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_stmt>> ppStmt,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>> pzTail,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Int,
        ffi.UnsignedInt,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_stmt>>,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>>)>()
external int sqlite3_prepare_v3(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> zSql,
  int nByte,
  int prepFlags,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_stmt>> ppStmt,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>> pzTail,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_finalize(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_step(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_reset(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_stmt_isexplain(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_stmt_readonly(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_column_count(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>)>()
external int sqlite3_bind_parameter_count(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Pointer<imp$1.sqlite3_char>)>()
external int sqlite3_bind_parameter_index(
  ffi.Pointer<imp$1.sqlite3_stmt> arg0,
  ffi.Pointer<imp$1.sqlite3_char> zName,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_char> Function(
        ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_column_name(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int N,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_char> Function(
        ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_column_table_name(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int N,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int,
        ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Pointer<ffi.Void>)>()
external int sqlite3_bind_blob64(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int index,
  ffi.Pointer<ffi.Void> data,
  int length,
  ffi.Pointer<ffi.Void> destructor,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int, ffi.Double)>()
external int sqlite3_bind_double(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int index,
  double data,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int, ffi.Int64)>()
external int sqlite3_bind_int64(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int index,
  int data,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external int sqlite3_bind_null(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int index,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int,
        ffi.Pointer<imp$1.sqlite3_char>, ffi.Int, ffi.Pointer<ffi.Void>)>()
external int sqlite3_bind_text(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int index,
  ffi.Pointer<imp$1.sqlite3_char> data,
  int length,
  ffi.Pointer<ffi.Void> destructor,
);

@ffi.Native<
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external ffi.Pointer<ffi.Void> sqlite3_column_blob(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int iCol,
);

@ffi.Native<ffi.Double Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external double sqlite3_column_double(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int iCol,
);

@ffi.Native<ffi.Int64 Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external int sqlite3_column_int64(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int iCol,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_char> Function(
        ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_column_text(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int iCol,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external int sqlite3_column_bytes(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int iCol,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_stmt>, ffi.Int)>()
external int sqlite3_column_type(
  ffi.Pointer<imp$1.sqlite3_stmt> pStmt,
  int iCol,
);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<imp$1.sqlite3_value>)>()
external ffi.Pointer<ffi.Void> sqlite3_value_blob(
  ffi.Pointer<imp$1.sqlite3_value> value,
);

@ffi.Native<ffi.Double Function(ffi.Pointer<imp$1.sqlite3_value>)>()
external double sqlite3_value_double(
  ffi.Pointer<imp$1.sqlite3_value> value,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_value>)>()
external int sqlite3_value_type(
  ffi.Pointer<imp$1.sqlite3_value> value,
);

@ffi.Native<ffi.Int64 Function(ffi.Pointer<imp$1.sqlite3_value>)>()
external int sqlite3_value_int64(
  ffi.Pointer<imp$1.sqlite3_value> value,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_char> Function(
        ffi.Pointer<imp$1.sqlite3_value>)>()
external ffi.Pointer<imp$1.sqlite3_char> sqlite3_value_text(
  ffi.Pointer<imp$1.sqlite3_value> value,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_value>)>()
external int sqlite3_value_bytes(
  ffi.Pointer<imp$1.sqlite3_value> value,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Int,
        ffi.Int,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                    ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                    ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>>,
        ffi.Pointer<
            ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>)>()
external int sqlite3_create_function_v2(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> zFunctionName,
  int nArg,
  int eTextRep,
  ffi.Pointer<ffi.Void> pApp,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>
      xFunc,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>
      xStep,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>>
      xFinal,
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
      xDestroy,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Int,
        ffi.Int,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                    ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                    ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>,
        ffi.Pointer<
            ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>)>()
external int sqlite3_create_window_function(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> zFunctionName,
  int nArg,
  int eTextRep,
  ffi.Pointer<ffi.Void> pApp,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>
      xStep,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>>
      xFinal,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>>
      xValue,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int,
                  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>>
      xInverse,
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
      xDestroy,
);

@ffi.Native<
    ffi.Pointer<ffi.Void> Function(
        ffi.Pointer<imp$1.sqlite3_context>, ffi.Int)>()
external ffi.Pointer<ffi.Void> sqlite3_aggregate_context(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
  int nBytes,
);

@ffi.Native<
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<imp$1.sqlite3_context>)>()
external ffi.Pointer<ffi.Void> sqlite3_user_data(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
);

@ffi.Native<
    ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Pointer<ffi.Void>,
        ffi.Uint64, ffi.Pointer<ffi.Void>)>()
external void sqlite3_result_blob64(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
  ffi.Pointer<ffi.Void> data,
  int length,
  ffi.Pointer<ffi.Void> destructor,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Double)>()
external void sqlite3_result_double(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
  double result,
);

@ffi.Native<
    ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>,
        ffi.Pointer<imp$1.sqlite3_char>, ffi.Int)>()
external void sqlite3_result_error(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
  ffi.Pointer<imp$1.sqlite3_char> msg,
  int length,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>, ffi.Int64)>()
external void sqlite3_result_int64(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
  int result,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>)>()
external void sqlite3_result_null(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
);

@ffi.Native<
    ffi.Void Function(ffi.Pointer<imp$1.sqlite3_context>,
        ffi.Pointer<imp$1.sqlite3_char>, ffi.Int, ffi.Pointer<ffi.Void>)>()
external void sqlite3_result_text(
  ffi.Pointer<imp$1.sqlite3_context> ctx,
  ffi.Pointer<imp$1.sqlite3_char> data,
  int length,
  ffi.Pointer<ffi.Void> destructor,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Int,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int,
                    ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Void>)>>,
        ffi.Pointer<
            ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>)>()
external int sqlite3_create_collation_v2(
  ffi.Pointer<imp$1.sqlite3> arg0,
  ffi.Pointer<imp$1.sqlite3_char> zName,
  int eTextRep,
  ffi.Pointer<ffi.Void> pArg,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int,
                  ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Void>)>>
      xCompare,
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
      xDestroy,
);

@ffi.Native<
    ffi.Pointer<imp$1.sqlite3_backup> Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>)>()
external ffi.Pointer<imp$1.sqlite3_backup> sqlite3_backup_init(
  ffi.Pointer<imp$1.sqlite3> pDestDb,
  ffi.Pointer<imp$1.sqlite3_char> zDestDb,
  ffi.Pointer<imp$1.sqlite3> pSrcDb,
  ffi.Pointer<imp$1.sqlite3_char> zSrcDb,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_backup>, ffi.Int)>()
external int sqlite3_backup_step(
  ffi.Pointer<imp$1.sqlite3_backup> p,
  int nPage,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_backup>)>()
external int sqlite3_backup_finish(
  ffi.Pointer<imp$1.sqlite3_backup> p,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_backup>)>()
external int sqlite3_backup_remaining(
  ffi.Pointer<imp$1.sqlite3_backup> p,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_backup>)>()
external int sqlite3_backup_pagecount(
  ffi.Pointer<imp$1.sqlite3_backup> p,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>()
external int sqlite3_auto_extension(
  ffi.Pointer<ffi.Void> xEntryPoint,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Int,
        ffi.VarArgs<
            (
              ffi.Int,
              ffi.Pointer<ffi.Int>,
            )>)>()
external int sqlite3_db_config(
  ffi.Pointer<imp$1.sqlite3> db,
  int op,
  int va,
  ffi.Pointer<ffi.Int> va$1,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_vfs>, ffi.Int)>()
external int sqlite3_vfs_register(
  ffi.Pointer<imp$1.sqlite3_vfs> arg0,
  int makeDflt,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_vfs>)>()
external int sqlite3_vfs_unregister(
  ffi.Pointer<imp$1.sqlite3_vfs> arg0,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Pointer<imp$1.sqlite3_char>,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_session>>)>()
external int sqlite3session_create(
  ffi.Pointer<imp$1.sqlite3> db,
  ffi.Pointer<imp$1.sqlite3_char> zDb,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_session>> ppSession,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<imp$1.sqlite3_session>)>()
external void sqlite3session_delete(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_session>, ffi.Int)>()
external int sqlite3session_enable(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
  int bEnable,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_session>, ffi.Int)>()
external int sqlite3session_indirect(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
  int bIndirect,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<ffi.Pointer<imp$1.sqlite3_changeset_iter>>,
        ffi.Int, ffi.Pointer<ffi.Void>)>()
external int sqlite3changeset_start(
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_changeset_iter>> pp,
  int nChangeset,
  ffi.Pointer<ffi.Void> pChangeset,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_changeset_iter>)>()
external int sqlite3changeset_finalize(
  ffi.Pointer<imp$1.sqlite3_changeset_iter> pIter,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_changeset_iter>)>()
external int sqlite3changeset_next(
  ffi.Pointer<imp$1.sqlite3_changeset_iter> pIter,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3_changeset_iter>,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>>,
        ffi.Pointer<ffi.Int>,
        ffi.Pointer<ffi.Int>,
        ffi.Pointer<ffi.Int>)>()
external int sqlite3changeset_op(
  ffi.Pointer<imp$1.sqlite3_changeset_iter> pIter,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_char>> pzTab,
  ffi.Pointer<ffi.Int> pnCol,
  ffi.Pointer<ffi.Int> pOp,
  ffi.Pointer<ffi.Int> pbIndirect,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_changeset_iter>, ffi.Int,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>()
external int sqlite3changeset_old(
  ffi.Pointer<imp$1.sqlite3_changeset_iter> pIter,
  int iVal,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>> ppValue,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_changeset_iter>, ffi.Int,
        ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>>)>()
external int sqlite3changeset_new(
  ffi.Pointer<imp$1.sqlite3_changeset_iter> pIter,
  int iVal,
  ffi.Pointer<ffi.Pointer<imp$1.sqlite3_value>> ppValue,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3>,
        ffi.Int,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Int Function(
                    ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>,
        ffi.Pointer<
            ffi.NativeFunction<
                ffi.Int Function(ffi.Pointer<ffi.Void> pCtx, ffi.Int eConflict,
                    ffi.Pointer<imp$1.sqlite3_changeset_iter> p)>>,
        ffi.Pointer<ffi.Void>)>()
external int sqlite3changeset_apply(
  ffi.Pointer<imp$1.sqlite3> db,
  int nChangeset,
  ffi.Pointer<ffi.Void> pChangeset,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Int Function(
                  ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>
      xFilter,
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Int Function(ffi.Pointer<ffi.Void> pCtx, ffi.Int eConflict,
                  ffi.Pointer<imp$1.sqlite3_changeset_iter> p)>>
      xConflict,
  ffi.Pointer<ffi.Void> pCtx,
);

@ffi.Native<
    ffi.Int Function(ffi.Int, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int>,
        ffi.Pointer<ffi.Pointer<ffi.Void>>)>()
external int sqlite3changeset_invert(
  int nIn,
  ffi.Pointer<ffi.Void> pIn,
  ffi.Pointer<ffi.Int> pnOut,
  ffi.Pointer<ffi.Pointer<ffi.Void>> ppOut,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_session>, ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Pointer<ffi.Char>>)>()
external int sqlite3session_diff(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
  ffi.Pointer<ffi.Char> zFromDb,
  ffi.Pointer<ffi.Char> zTbl,
  ffi.Pointer<ffi.Pointer<ffi.Char>> pzErrMsg,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_session>, ffi.Pointer<ffi.Int>,
        ffi.Pointer<ffi.Pointer<ffi.Void>>)>()
external int sqlite3session_patchset(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
  ffi.Pointer<ffi.Int> pnPatchset,
  ffi.Pointer<ffi.Pointer<ffi.Void>> ppPatchset,
);

@ffi.Native<
    ffi.Int Function(ffi.Pointer<imp$1.sqlite3_session>, ffi.Pointer<ffi.Int>,
        ffi.Pointer<ffi.Pointer<ffi.Void>>)>()
external int sqlite3session_changeset(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
  ffi.Pointer<ffi.Int> pnChangeset,
  ffi.Pointer<ffi.Pointer<ffi.Void>> ppChangeset,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<imp$1.sqlite3_session>)>()
external int sqlite3session_isempty(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<imp$1.sqlite3_session>, ffi.Pointer<ffi.Char>)>()
external int sqlite3session_attach(
  ffi.Pointer<imp$1.sqlite3_session> pSession,
  ffi.Pointer<ffi.Char> zTab,
);

const addresses = _SymbolAddresses();

final class _SymbolAddresses implements imp$1.SharedSymbolAddresses {
  const _SymbolAddresses();
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
      get sqlite3_free => ffi.Native.addressOf(self.sqlite3_free);
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<imp$1.sqlite3_session>)>>
      get sqlite3session_delete =>
          ffi.Native.addressOf(self.sqlite3session_delete);
  ffi.Pointer<
          ffi.NativeFunction<
              ffi.Int Function(ffi.Pointer<imp$1.sqlite3_changeset_iter>)>>
      get sqlite3changeset_finalize =>
          ffi.Native.addressOf(self.sqlite3changeset_finalize);
}
