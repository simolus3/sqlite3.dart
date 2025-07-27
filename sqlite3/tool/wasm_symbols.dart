import 'dart:io';

/// Writes flags for clang that will `-Wl,--export` all symbols used by the
/// `sqlite3` Dart package on the web.
void main(List<String> args) {
  final symbols = [...stableFunctions, ...unstable];

  final output = File(args[0]);
  output.writeAsStringSync(symbols.map((e) => '-Wl,--export=$e').join(' '));
}

// Functions we can assume to be exported from `sqlite3.wasm` unconditionally.
// We regularly add bindings to additional SQLite functions that would not be
// exported from older `sqlite3.wasm` bundles which we still support. We have
// to generate those as optional functions.
const stableFunctions = {
  'dart_sqlite3_malloc',
  'dart_sqlite3_free',
  'dart_sqlite3_register_vfs',
  'dart_sqlite3_create_scalar_function',
  'dart_sqlite3_create_aggregate_function',
  'sqlite3_temp_directory',
  'sqlite3_open_v2',
  'sqlite3_close_v2',
  'sqlite3_column_name',
  'sqlite3_extended_result_codes',
  'sqlite3_extended_errcode',
  'sqlite3_errmsg',
  'sqlite3_errstr',
  'sqlite3_free',
  'sqlite3_libversion',
  'sqlite3_sourceid',
  'sqlite3_libversion_number',
  'sqlite3_last_insert_rowid',
  'sqlite3_changes',
  'sqlite3_exec',
  'sqlite3_get_autocommit',
  'sqlite3_prepare_v2',
  'sqlite3_prepare_v3',
  'sqlite3_finalize',
  'sqlite3_step',
  'sqlite3_reset',
  'sqlite3_stmt_isexplain',
  'sqlite3_stmt_readonly',
  'sqlite3_column_count',
  'sqlite3_bind_parameter_count',
  'sqlite3_bind_parameter_index',
  'sqlite3_bind_blob64',
  'sqlite3_bind_double',
  'sqlite3_bind_int64',
  'sqlite3_bind_null',
  'sqlite3_bind_text',
  'sqlite3_column_blob',
  'sqlite3_column_double',
  'sqlite3_column_int64',
  'sqlite3_column_text',
  'sqlite3_column_bytes',
  'sqlite3_column_type',
  'sqlite3_value_blob',
  'sqlite3_value_double',
  'sqlite3_value_type',
  'sqlite3_value_int64',
  'sqlite3_value_text',
  'sqlite3_value_bytes',
  'sqlite3_aggregate_context',
  'sqlite3_user_data',
  'sqlite3_result_blob64',
  'sqlite3_result_double',
  'sqlite3_result_error',
  'sqlite3_result_int64',
  'sqlite3_result_null',
  'sqlite3_result_text',
  'sqlite3_vfs_unregister',
};

/// Newer functions that aren't available in older WASM bundldes.
const unstable = {
  'sqlite3_db_config',
  'sqlite3_initialize',
  'dart_sqlite3_updates',
  'dart_sqlite3_commits',
  'dart_sqlite3_rollbacks',
  'dart_sqlite3_db_config_int',
  'sqlite3_error_offset',
  'sqlite3_result_subtype',
  'sqlite3_value_subtype',
  'dart_sqlite3_create_window_function',
  'dart_sqlite3_create_collation',
  'sqlite3session_create',
  'sqlite3session_delete',
  'sqlite3session_enable',
  'sqlite3session_indirect',
  'sqlite3session_isempty',
  'sqlite3session_attach',
  'sqlite3session_diff',
  'sqlite3session_patchset',
  'sqlite3session_changeset',
  'sqlite3changeset_invert',
  'sqlite3changeset_start',
  'sqlite3changeset_finalize',
  'sqlite3changeset_next',
  'sqlite3changeset_op',
  'sqlite3changeset_old',
  'sqlite3changeset_new',
  'dart_sqlite3changeset_apply',
};
