// Generated by tool/generate_bindings.dart
// ignore_for_file: type=lint
import 'dart:ffi' as ffi;
import 'native.dart' as native;
import 'shared.dart';

final class NativeAssetsLibrary implements SqliteLibrary {
  @override
  ffi.Pointer<sqlite3_char> get sqlite3_temp_directory {
    return native.sqlite3_temp_directory;
  }

  @override
  set sqlite3_temp_directory(ffi.Pointer<sqlite3_char> value) {
    native.sqlite3_temp_directory = value;
  }

  @override
  int sqlite3_initialize() {
    return native.sqlite3_initialize();
  }

  @override
  int sqlite3_open_v2(
      ffi.Pointer<sqlite3_char> filename,
      ffi.Pointer<ffi.Pointer<sqlite3>> ppDb,
      int flags,
      ffi.Pointer<sqlite3_char> zVfs) {
    return native.sqlite3_open_v2(filename, ppDb, flags, zVfs);
  }

  @override
  int sqlite3_close_v2(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_close_v2(db);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_db_filename(
      ffi.Pointer<sqlite3> db, ffi.Pointer<sqlite3_char> zDbName) {
    return native.sqlite3_db_filename(db, zDbName);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_compileoption_get(int N) {
    return native.sqlite3_compileoption_get(N);
  }

  @override
  int sqlite3_extended_result_codes(ffi.Pointer<sqlite3> db, int onoff) {
    return native.sqlite3_extended_result_codes(db, onoff);
  }

  @override
  int sqlite3_extended_errcode(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_extended_errcode(db);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_errmsg(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_errmsg(db);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_errstr(int code) {
    return native.sqlite3_errstr(code);
  }

  @override
  int sqlite3_error_offset(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_error_offset(db);
  }

  @override
  void sqlite3_free(ffi.Pointer<ffi.Void> ptr) {
    return native.sqlite3_free(ptr);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_libversion() {
    return native.sqlite3_libversion();
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_sourceid() {
    return native.sqlite3_sourceid();
  }

  @override
  int sqlite3_libversion_number() {
    return native.sqlite3_libversion_number();
  }

  @override
  int sqlite3_last_insert_rowid(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_last_insert_rowid(db);
  }

  @override
  int sqlite3_changes(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_changes(db);
  }

  @override
  int sqlite3_exec(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<sqlite3_char> sql,
      ffi.Pointer<ffi.Void> callback,
      ffi.Pointer<ffi.Void> argToCb,
      ffi.Pointer<ffi.Pointer<sqlite3_char>> errorOut) {
    return native.sqlite3_exec(db, sql, callback, argToCb, errorOut);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_update_hook(
      ffi.Pointer<sqlite3> arg0,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Int,
                      ffi.Pointer<sqlite3_char>,
                      ffi.Pointer<sqlite3_char>,
                      ffi.Int64)>>
          arg1,
      ffi.Pointer<ffi.Void> arg2) {
    return native.sqlite3_update_hook(arg0, arg1, arg2);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_commit_hook(
      ffi.Pointer<sqlite3> arg0,
      ffi.Pointer<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.Void>)>>
          arg1,
      ffi.Pointer<ffi.Void> arg2) {
    return native.sqlite3_commit_hook(arg0, arg1, arg2);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_rollback_hook(
      ffi.Pointer<sqlite3> arg0,
      ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
          arg1,
      ffi.Pointer<ffi.Void> arg2) {
    return native.sqlite3_rollback_hook(arg0, arg1, arg2);
  }

  @override
  int sqlite3_get_autocommit(ffi.Pointer<sqlite3> db) {
    return native.sqlite3_get_autocommit(db);
  }

  @override
  int sqlite3_prepare_v2(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<sqlite3_char> zSql,
      int nByte,
      ffi.Pointer<ffi.Pointer<sqlite3_stmt>> ppStmt,
      ffi.Pointer<ffi.Pointer<sqlite3_char>> pzTail) {
    return native.sqlite3_prepare_v2(db, zSql, nByte, ppStmt, pzTail);
  }

  @override
  int sqlite3_prepare_v3(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<sqlite3_char> zSql,
      int nByte,
      int prepFlags,
      ffi.Pointer<ffi.Pointer<sqlite3_stmt>> ppStmt,
      ffi.Pointer<ffi.Pointer<sqlite3_char>> pzTail) {
    return native.sqlite3_prepare_v3(
        db, zSql, nByte, prepFlags, ppStmt, pzTail);
  }

  @override
  int sqlite3_finalize(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_finalize(pStmt);
  }

  @override
  int sqlite3_step(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_step(pStmt);
  }

  @override
  int sqlite3_reset(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_reset(pStmt);
  }

  @override
  int sqlite3_stmt_isexplain(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_stmt_isexplain(pStmt);
  }

  @override
  int sqlite3_stmt_readonly(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_stmt_readonly(pStmt);
  }

  @override
  int sqlite3_column_count(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_column_count(pStmt);
  }

  @override
  int sqlite3_bind_parameter_count(ffi.Pointer<sqlite3_stmt> pStmt) {
    return native.sqlite3_bind_parameter_count(pStmt);
  }

  @override
  int sqlite3_bind_parameter_index(
      ffi.Pointer<sqlite3_stmt> arg0, ffi.Pointer<sqlite3_char> zName) {
    return native.sqlite3_bind_parameter_index(arg0, zName);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_column_name(
      ffi.Pointer<sqlite3_stmt> pStmt, int N) {
    return native.sqlite3_column_name(pStmt, N);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_column_table_name(
      ffi.Pointer<sqlite3_stmt> pStmt, int N) {
    return native.sqlite3_column_table_name(pStmt, N);
  }

  @override
  int sqlite3_bind_blob64(
      ffi.Pointer<sqlite3_stmt> pStmt,
      int index,
      ffi.Pointer<ffi.Void> data,
      int length,
      ffi.Pointer<ffi.Void> destructor) {
    return native.sqlite3_bind_blob64(pStmt, index, data, length, destructor);
  }

  @override
  int sqlite3_bind_double(
      ffi.Pointer<sqlite3_stmt> pStmt, int index, double data) {
    return native.sqlite3_bind_double(pStmt, index, data);
  }

  @override
  int sqlite3_bind_int64(ffi.Pointer<sqlite3_stmt> pStmt, int index, int data) {
    return native.sqlite3_bind_int64(pStmt, index, data);
  }

  @override
  int sqlite3_bind_null(ffi.Pointer<sqlite3_stmt> pStmt, int index) {
    return native.sqlite3_bind_null(pStmt, index);
  }

  @override
  int sqlite3_bind_text(
      ffi.Pointer<sqlite3_stmt> pStmt,
      int index,
      ffi.Pointer<sqlite3_char> data,
      int length,
      ffi.Pointer<ffi.Void> destructor) {
    return native.sqlite3_bind_text(pStmt, index, data, length, destructor);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_column_blob(
      ffi.Pointer<sqlite3_stmt> pStmt, int iCol) {
    return native.sqlite3_column_blob(pStmt, iCol);
  }

  @override
  double sqlite3_column_double(ffi.Pointer<sqlite3_stmt> pStmt, int iCol) {
    return native.sqlite3_column_double(pStmt, iCol);
  }

  @override
  int sqlite3_column_int64(ffi.Pointer<sqlite3_stmt> pStmt, int iCol) {
    return native.sqlite3_column_int64(pStmt, iCol);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_column_text(
      ffi.Pointer<sqlite3_stmt> pStmt, int iCol) {
    return native.sqlite3_column_text(pStmt, iCol);
  }

  @override
  int sqlite3_column_bytes(ffi.Pointer<sqlite3_stmt> pStmt, int iCol) {
    return native.sqlite3_column_bytes(pStmt, iCol);
  }

  @override
  int sqlite3_column_type(ffi.Pointer<sqlite3_stmt> pStmt, int iCol) {
    return native.sqlite3_column_type(pStmt, iCol);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_value_blob(ffi.Pointer<sqlite3_value> value) {
    return native.sqlite3_value_blob(value);
  }

  @override
  double sqlite3_value_double(ffi.Pointer<sqlite3_value> value) {
    return native.sqlite3_value_double(value);
  }

  @override
  int sqlite3_value_type(ffi.Pointer<sqlite3_value> value) {
    return native.sqlite3_value_type(value);
  }

  @override
  int sqlite3_value_int64(ffi.Pointer<sqlite3_value> value) {
    return native.sqlite3_value_int64(value);
  }

  @override
  ffi.Pointer<sqlite3_char> sqlite3_value_text(
      ffi.Pointer<sqlite3_value> value) {
    return native.sqlite3_value_text(value);
  }

  @override
  int sqlite3_value_bytes(ffi.Pointer<sqlite3_value> value) {
    return native.sqlite3_value_bytes(value);
  }

  @override
  int sqlite3_create_function_v2(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<sqlite3_char> zFunctionName,
      int nArg,
      int eTextRep,
      ffi.Pointer<ffi.Void> pApp,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Void Function(ffi.Pointer<sqlite3_context>, ffi.Int,
                      ffi.Pointer<ffi.Pointer<sqlite3_value>>)>>
          xFunc,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Void Function(ffi.Pointer<sqlite3_context>, ffi.Int,
                      ffi.Pointer<ffi.Pointer<sqlite3_value>>)>>
          xStep,
      ffi.Pointer<
              ffi
              .NativeFunction<ffi.Void Function(ffi.Pointer<sqlite3_context>)>>
          xFinal,
      ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
          xDestroy) {
    return native.sqlite3_create_function_v2(db, zFunctionName, nArg, eTextRep,
        pApp, xFunc, xStep, xFinal, xDestroy);
  }

  @override
  int sqlite3_create_window_function(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<sqlite3_char> zFunctionName,
      int nArg,
      int eTextRep,
      ffi.Pointer<ffi.Void> pApp,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Void Function(ffi.Pointer<sqlite3_context>, ffi.Int,
                      ffi.Pointer<ffi.Pointer<sqlite3_value>>)>>
          xStep,
      ffi.Pointer<
              ffi
              .NativeFunction<ffi.Void Function(ffi.Pointer<sqlite3_context>)>>
          xFinal,
      ffi.Pointer<
              ffi
              .NativeFunction<ffi.Void Function(ffi.Pointer<sqlite3_context>)>>
          xValue,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Void Function(ffi.Pointer<sqlite3_context>, ffi.Int,
                      ffi.Pointer<ffi.Pointer<sqlite3_value>>)>>
          xInverse,
      ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
          xDestroy) {
    return native.sqlite3_create_window_function(db, zFunctionName, nArg,
        eTextRep, pApp, xStep, xFinal, xValue, xInverse, xDestroy);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_aggregate_context(
      ffi.Pointer<sqlite3_context> ctx, int nBytes) {
    return native.sqlite3_aggregate_context(ctx, nBytes);
  }

  @override
  ffi.Pointer<ffi.Void> sqlite3_user_data(ffi.Pointer<sqlite3_context> ctx) {
    return native.sqlite3_user_data(ctx);
  }

  @override
  void sqlite3_result_blob64(
      ffi.Pointer<sqlite3_context> ctx,
      ffi.Pointer<ffi.Void> data,
      int length,
      ffi.Pointer<ffi.Void> destructor) {
    return native.sqlite3_result_blob64(ctx, data, length, destructor);
  }

  @override
  void sqlite3_result_double(ffi.Pointer<sqlite3_context> ctx, double result) {
    return native.sqlite3_result_double(ctx, result);
  }

  @override
  void sqlite3_result_error(ffi.Pointer<sqlite3_context> ctx,
      ffi.Pointer<sqlite3_char> msg, int length) {
    return native.sqlite3_result_error(ctx, msg, length);
  }

  @override
  void sqlite3_result_int64(ffi.Pointer<sqlite3_context> ctx, int result) {
    return native.sqlite3_result_int64(ctx, result);
  }

  @override
  void sqlite3_result_null(ffi.Pointer<sqlite3_context> ctx) {
    return native.sqlite3_result_null(ctx);
  }

  @override
  void sqlite3_result_text(
      ffi.Pointer<sqlite3_context> ctx,
      ffi.Pointer<sqlite3_char> data,
      int length,
      ffi.Pointer<ffi.Void> destructor) {
    return native.sqlite3_result_text(ctx, data, length, destructor);
  }

  @override
  int sqlite3_create_collation_v2(
      ffi.Pointer<sqlite3> arg0,
      ffi.Pointer<sqlite3_char> zName,
      int eTextRep,
      ffi.Pointer<ffi.Void> pArg,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int,
                      ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Void>)>>
          xCompare,
      ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>
          xDestroy) {
    return native.sqlite3_create_collation_v2(
        arg0, zName, eTextRep, pArg, xCompare, xDestroy);
  }

  @override
  ffi.Pointer<sqlite3_backup> sqlite3_backup_init(
      ffi.Pointer<sqlite3> pDestDb,
      ffi.Pointer<sqlite3_char> zDestDb,
      ffi.Pointer<sqlite3> pSrcDb,
      ffi.Pointer<sqlite3_char> zSrcDb) {
    return native.sqlite3_backup_init(pDestDb, zDestDb, pSrcDb, zSrcDb);
  }

  @override
  int sqlite3_backup_step(ffi.Pointer<sqlite3_backup> p, int nPage) {
    return native.sqlite3_backup_step(p, nPage);
  }

  @override
  int sqlite3_backup_finish(ffi.Pointer<sqlite3_backup> p) {
    return native.sqlite3_backup_finish(p);
  }

  @override
  int sqlite3_backup_remaining(ffi.Pointer<sqlite3_backup> p) {
    return native.sqlite3_backup_remaining(p);
  }

  @override
  int sqlite3_backup_pagecount(ffi.Pointer<sqlite3_backup> p) {
    return native.sqlite3_backup_pagecount(p);
  }

  @override
  int sqlite3_auto_extension(ffi.Pointer<ffi.Void> xEntryPoint) {
    return native.sqlite3_auto_extension(xEntryPoint);
  }

  @override
  int sqlite3_db_config(
      ffi.Pointer<sqlite3> db, int op, int va, ffi.Pointer<ffi.Int> va1) {
    return native.sqlite3_db_config(db, op, va, va1);
  }

  @override
  int sqlite3_vfs_register(ffi.Pointer<sqlite3_vfs> arg0, int makeDflt) {
    return native.sqlite3_vfs_register(arg0, makeDflt);
  }

  @override
  int sqlite3_vfs_unregister(ffi.Pointer<sqlite3_vfs> arg0) {
    return native.sqlite3_vfs_unregister(arg0);
  }

  @override
  int sqlite3changegroup_add(ffi.Pointer<sqlite3_changegroup> arg0, int nData,
      ffi.Pointer<ffi.Void> pData) {
    return native.sqlite3changegroup_add(arg0, nData, pData);
  }

  @override
  int sqlite3changegroup_add_change(ffi.Pointer<sqlite3_changegroup> arg0,
      ffi.Pointer<sqlite3_changeset_iter> arg1) {
    return native.sqlite3changegroup_add_change(arg0, arg1);
  }

  @override
  int sqlite3changeset_apply_strm(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>
          xFilter,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx,
                      ffi.Int eConflict,
                      ffi.Pointer<sqlite3_changeset_iter> p)>>
          xConflict,
      ffi.Pointer<ffi.Void> pCtx) {
    return native.sqlite3changeset_apply_strm(
        db, xInput, pIn, xFilter, xConflict, pCtx);
  }

  @override
  int sqlite3changeset_apply_v2_strm(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>
          xFilter,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx,
                      ffi.Int eConflict,
                      ffi.Pointer<sqlite3_changeset_iter> p)>>
          xConflict,
      ffi.Pointer<ffi.Void> pCtx,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppRebase,
      ffi.Pointer<ffi.Int> pnRebase,
      int flags) {
    return native.sqlite3changeset_apply_v2_strm(
        db, xInput, pIn, xFilter, xConflict, pCtx, ppRebase, pnRebase, flags);
  }

  @override
  int sqlite3changeset_concat_strm(
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInputA,
      ffi.Pointer<ffi.Void> pInA,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInputB,
      ffi.Pointer<ffi.Void> pInB,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void> pOut,
                      ffi.Pointer<ffi.Void> pData, ffi.Int nData)>>
          xOutput,
      ffi.Pointer<ffi.Void> pOut) {
    return native.sqlite3changeset_concat_strm(
        xInputA, pInA, xInputB, pInB, xOutput, pOut);
  }

  @override
  int sqlite3changeset_invert_strm(
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void> pOut,
                      ffi.Pointer<ffi.Void> pData, ffi.Int nData)>>
          xOutput,
      ffi.Pointer<ffi.Void> pOut) {
    return native.sqlite3changeset_invert_strm(xInput, pIn, xOutput, pOut);
  }

  @override
  int sqlite3changeset_start_strm(
      ffi.Pointer<ffi.Pointer<sqlite3_changeset_iter>> pp,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn) {
    return native.sqlite3changeset_start_strm(pp, xInput, pIn);
  }

  @override
  int sqlite3changeset_start_v2_strm(
      ffi.Pointer<ffi.Pointer<sqlite3_changeset_iter>> pp,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn,
      int flags) {
    return native.sqlite3changeset_start_v2_strm(pp, xInput, pIn, flags);
  }

  @override
  int sqlite3session_changeset_strm(
      ffi.Pointer<sqlite3_session> pSession,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void> pOut,
                      ffi.Pointer<ffi.Void> pData, ffi.Int nData)>>
          xOutput,
      ffi.Pointer<ffi.Void> pOut) {
    return native.sqlite3session_changeset_strm(pSession, xOutput, pOut);
  }

  @override
  int sqlite3session_patchset_strm(
      ffi.Pointer<sqlite3_session> pSession,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void> pOut,
                      ffi.Pointer<ffi.Void> pData, ffi.Int nData)>>
          xOutput,
      ffi.Pointer<ffi.Void> pOut) {
    return native.sqlite3session_patchset_strm(pSession, xOutput, pOut);
  }

  @override
  int sqlite3changegroup_add_strm(
      ffi.Pointer<sqlite3_changegroup> arg0,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn) {
    return native.sqlite3changegroup_add_strm(arg0, xInput, pIn);
  }

  @override
  int sqlite3changegroup_output_strm(
      ffi.Pointer<sqlite3_changegroup> arg0,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void> pOut,
                      ffi.Pointer<ffi.Void> pData, ffi.Int nData)>>
          xOutput,
      ffi.Pointer<ffi.Void> pOut) {
    return native.sqlite3changegroup_output_strm(arg0, xOutput, pOut);
  }

  @override
  int sqlite3rebaser_rebase_strm(
      ffi.Pointer<sqlite3_rebaser> pRebaser,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pIn,
                      ffi.Pointer<ffi.Void> pData,
                      ffi.Pointer<ffi.Int> pnData)>>
          xInput,
      ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(ffi.Pointer<ffi.Void> pOut,
                      ffi.Pointer<ffi.Void> pData, ffi.Int nData)>>
          xOutput,
      ffi.Pointer<ffi.Void> pOut) {
    return native.sqlite3rebaser_rebase_strm(
        pRebaser, xInput, pIn, xOutput, pOut);
  }

  @override
  void sqlite3changegroup_delete(ffi.Pointer<sqlite3_changegroup> arg0) {
    return native.sqlite3changegroup_delete(arg0);
  }

  @override
  int sqlite3changegroup_new(ffi.Pointer<ffi.Pointer<sqlite3_changegroup>> pp) {
    return native.sqlite3changegroup_new(pp);
  }

  @override
  int sqlite3changegroup_output(ffi.Pointer<sqlite3_changegroup> arg0,
      ffi.Pointer<ffi.Int> pnData, ffi.Pointer<ffi.Pointer<ffi.Void>> ppData) {
    return native.sqlite3changegroup_output(arg0, pnData, ppData);
  }

  @override
  int sqlite3changegroup_schema(ffi.Pointer<sqlite3_changegroup> arg0,
      ffi.Pointer<sqlite3> arg1, ffi.Pointer<ffi.Char> zDb) {
    return native.sqlite3changegroup_schema(arg0, arg1, zDb);
  }

  @override
  int sqlite3changeset_apply(
      ffi.Pointer<sqlite3> db,
      int nChangeset,
      ffi.Pointer<ffi.Void> pChangeset,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>
          xFilter,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx,
                      ffi.Int eConflict,
                      ffi.Pointer<sqlite3_changeset_iter> p)>>
          xConflict,
      ffi.Pointer<ffi.Void> pCtx) {
    return native.sqlite3changeset_apply(
        db, nChangeset, pChangeset, xFilter, xConflict, pCtx);
  }

  @override
  int sqlite3changeset_apply_v2(
      ffi.Pointer<sqlite3> db,
      int nChangeset,
      ffi.Pointer<ffi.Void> pChangeset,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>
          xFilter,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx,
                      ffi.Int eConflict,
                      ffi.Pointer<sqlite3_changeset_iter> p)>>
          xConflict,
      ffi.Pointer<ffi.Void> pCtx,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppRebase,
      ffi.Pointer<ffi.Int> pnRebase,
      int flags) {
    return native.sqlite3changeset_apply_v2(db, nChangeset, pChangeset, xFilter,
        xConflict, pCtx, ppRebase, pnRebase, flags);
  }

  @override
  int sqlite3changeset_concat(
      int nA,
      ffi.Pointer<ffi.Void> pA,
      int nB,
      ffi.Pointer<ffi.Void> pB,
      ffi.Pointer<ffi.Int> pnOut,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppOut) {
    return native.sqlite3changeset_concat(nA, pA, nB, pB, pnOut, ppOut);
  }

  @override
  int sqlite3changeset_conflict(ffi.Pointer<sqlite3_changeset_iter> pIter,
      int iVal, ffi.Pointer<ffi.Pointer<sqlite3_value>> ppValue) {
    return native.sqlite3changeset_conflict(pIter, iVal, ppValue);
  }

  @override
  int sqlite3changeset_finalize(ffi.Pointer<sqlite3_changeset_iter> pIter) {
    return native.sqlite3changeset_finalize(pIter);
  }

  @override
  int sqlite3changeset_fk_conflicts(
      ffi.Pointer<sqlite3_changeset_iter> pIter, ffi.Pointer<ffi.Int> pnOut) {
    return native.sqlite3changeset_fk_conflicts(pIter, pnOut);
  }

  @override
  int sqlite3changeset_invert(int nIn, ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<ffi.Int> pnOut, ffi.Pointer<ffi.Pointer<ffi.Void>> ppOut) {
    return native.sqlite3changeset_invert(nIn, pIn, pnOut, ppOut);
  }

  @override
  int sqlite3changeset_new(ffi.Pointer<sqlite3_changeset_iter> pIter, int iVal,
      ffi.Pointer<ffi.Pointer<sqlite3_value>> ppValue) {
    return native.sqlite3changeset_new(pIter, iVal, ppValue);
  }

  @override
  int sqlite3changeset_next(ffi.Pointer<sqlite3_changeset_iter> pIter) {
    return native.sqlite3changeset_next(pIter);
  }

  @override
  int sqlite3changeset_old(ffi.Pointer<sqlite3_changeset_iter> pIter, int iVal,
      ffi.Pointer<ffi.Pointer<sqlite3_value>> ppValue) {
    return native.sqlite3changeset_old(pIter, iVal, ppValue);
  }

  @override
  int sqlite3changeset_op(
      ffi.Pointer<sqlite3_changeset_iter> pIter,
      ffi.Pointer<ffi.Pointer<ffi.Char>> pzTab,
      ffi.Pointer<ffi.Int> pnCol,
      ffi.Pointer<ffi.Int> pOp,
      ffi.Pointer<ffi.Int> pbIndirect) {
    return native.sqlite3changeset_op(pIter, pzTab, pnCol, pOp, pbIndirect);
  }

  @override
  int sqlite3changeset_pk(
      ffi.Pointer<sqlite3_changeset_iter> pIter,
      ffi.Pointer<ffi.Pointer<ffi.UnsignedChar>> pabPK,
      ffi.Pointer<ffi.Int> pnCol) {
    return native.sqlite3changeset_pk(pIter, pabPK, pnCol);
  }

  @override
  int sqlite3changeset_start(
      ffi.Pointer<ffi.Pointer<sqlite3_changeset_iter>> pp,
      int nChangeset,
      ffi.Pointer<ffi.Void> pChangeset) {
    return native.sqlite3changeset_start(pp, nChangeset, pChangeset);
  }

  @override
  int sqlite3changeset_start_v2(
      ffi.Pointer<ffi.Pointer<sqlite3_changeset_iter>> pp,
      int nChangeset,
      ffi.Pointer<ffi.Void> pChangeset,
      int flags) {
    return native.sqlite3changeset_start_v2(pp, nChangeset, pChangeset, flags);
  }

  @override
  int sqlite3changeset_upgrade(
      ffi.Pointer<sqlite3> db,
      ffi.Pointer<ffi.Char> zDb,
      int nIn,
      ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<ffi.Int> pnOut,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppOut) {
    return native.sqlite3changeset_upgrade(db, zDb, nIn, pIn, pnOut, ppOut);
  }

  @override
  int sqlite3rebaser_configure(ffi.Pointer<sqlite3_rebaser> arg0, int nRebase,
      ffi.Pointer<ffi.Void> pRebase) {
    return native.sqlite3rebaser_configure(arg0, nRebase, pRebase);
  }

  @override
  int sqlite3rebaser_create(ffi.Pointer<ffi.Pointer<sqlite3_rebaser>> ppNew) {
    return native.sqlite3rebaser_create(ppNew);
  }

  @override
  void sqlite3rebaser_delete(ffi.Pointer<sqlite3_rebaser> p) {
    return native.sqlite3rebaser_delete(p);
  }

  @override
  int sqlite3rebaser_rebase(
      ffi.Pointer<sqlite3_rebaser> arg0,
      int nIn,
      ffi.Pointer<ffi.Void> pIn,
      ffi.Pointer<ffi.Int> pnOut,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppOut) {
    return native.sqlite3rebaser_rebase(arg0, nIn, pIn, pnOut, ppOut);
  }

  @override
  int sqlite3session_attach(
      ffi.Pointer<sqlite3_session> pSession, ffi.Pointer<ffi.Char> zTab) {
    return native.sqlite3session_attach(pSession, zTab);
  }

  @override
  int sqlite3session_changeset(
      ffi.Pointer<sqlite3_session> pSession,
      ffi.Pointer<ffi.Int> pnChangeset,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppChangeset) {
    return native.sqlite3session_changeset(pSession, pnChangeset, ppChangeset);
  }

  @override
  int sqlite3session_changeset_size(ffi.Pointer<sqlite3_session> pSession) {
    return native.sqlite3session_changeset_size(pSession);
  }

  @override
  int sqlite3session_config(int op, ffi.Pointer<ffi.Void> pArg) {
    return native.sqlite3session_config(op, pArg);
  }

  @override
  int sqlite3session_create(ffi.Pointer<sqlite3> db, ffi.Pointer<ffi.Char> zDb,
      ffi.Pointer<ffi.Pointer<sqlite3_session>> ppSession) {
    return native.sqlite3session_create(db, zDb, ppSession);
  }

  @override
  void sqlite3session_delete(ffi.Pointer<sqlite3_session> pSession) {
    return native.sqlite3session_delete(pSession);
  }

  @override
  int sqlite3session_diff(
      ffi.Pointer<sqlite3_session> pSession,
      ffi.Pointer<ffi.Char> zFromDb,
      ffi.Pointer<ffi.Char> zTbl,
      ffi.Pointer<ffi.Pointer<ffi.Char>> pzErrMsg) {
    return native.sqlite3session_diff(pSession, zFromDb, zTbl, pzErrMsg);
  }

  @override
  int sqlite3session_enable(
      ffi.Pointer<sqlite3_session> pSession, int bEnable) {
    return native.sqlite3session_enable(pSession, bEnable);
  }

  @override
  int sqlite3session_indirect(
      ffi.Pointer<sqlite3_session> pSession, int bIndirect) {
    return native.sqlite3session_indirect(pSession, bIndirect);
  }

  @override
  int sqlite3session_isempty(ffi.Pointer<sqlite3_session> pSession) {
    return native.sqlite3session_isempty(pSession);
  }

  @override
  int sqlite3session_memory_used(ffi.Pointer<sqlite3_session> pSession) {
    return native.sqlite3session_memory_used(pSession);
  }

  @override
  int sqlite3session_object_config(
      ffi.Pointer<sqlite3_session> arg0, int op, ffi.Pointer<ffi.Void> pArg) {
    return native.sqlite3session_object_config(arg0, op, pArg);
  }

  @override
  int sqlite3session_patchset(
      ffi.Pointer<sqlite3_session> pSession,
      ffi.Pointer<ffi.Int> pnPatchset,
      ffi.Pointer<ffi.Pointer<ffi.Void>> ppPatchset) {
    return native.sqlite3session_patchset(pSession, pnPatchset, ppPatchset);
  }

  @override
  void sqlite3session_table_filter(
      ffi.Pointer<sqlite3_session> pSession,
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Int Function(
                      ffi.Pointer<ffi.Void> pCtx, ffi.Pointer<ffi.Char> zTab)>>
          xFilter,
      ffi.Pointer<ffi.Void> pCtx) {
    return native.sqlite3session_table_filter(pSession, xFilter, pCtx);
  }
}
