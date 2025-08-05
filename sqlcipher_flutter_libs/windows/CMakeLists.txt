cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlcipher_flutter_libs")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "sqlcipher_flutter_libs_plugin")

# Essentially, the idea of this build script is to compile a sqlite3.dll
# and make Fluter bundle that with the final app.
# It looks like we can't avoid building a sqlite3_flutter_libs.dll too,
# but that's not on me.

add_library(${PLUGIN_NAME} SHARED
  "sqlite3_flutter_libs_plugin.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)


set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)

# Using a prebuilt sqlcipher amalgation because building it requires TCL/TK which no one has.
file(DOWNLOAD "https://fsn1.your-objectstorage.com/simon-public/assets/sqlcipher/v4_10_0.c" "${CMAKE_CURRENT_BINARY_DIR}/sqlcipher.c" EXPECTED_HASH SHA512=ea4ad61eb636a3b6b0a4d8a1b57b51af187ac8724fe853bd9ce58c7ee4054bd62c4e6d7d11788c8af9ff8e95c6a52eb36a41062172022bc1cbc0567de0aec8c1)

add_library(sqlite3 SHARED "sqlite3_flutter.c")
target_include_directories(sqlite3 PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
set_property(SOURCE "sqlite3_flutter.c" APPEND PROPERTY OBJECT_DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/sqlcipher.c")
target_link_libraries(sqlite3 PRIVATE OpenSSL::Crypto)

# Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
# SQLITE_HAS_CODEC, SQLITE_EXTRA_INIT, SQLITE_EXTRA_SHUTDOWN are required for sqlcipher
target_compile_definitions(sqlite3 PRIVATE
  SQLITE_HAS_CODEC
  SQLITE_EXTRA_INIT=sqlcipher_extra_init
  SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown
  HAVE_STDINT_H
  SQLITE_DQS=0
  SQLITE_THREADSAFE=1
  SQLITE_DEFAULT_MEMSTATUS=0
  SQLITE_TEMP_STORE=2
  SQLITE_MAX_EXPR_DEPTH=0
  SQLITE_OMIT_AUTHORIZATION
  SQLITE_OMIT_DECLTYPE
  SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_PROGRESS_CALLBACK
  SQLITE_OMIT_SHARED_CACHE
  SQLITE_OMIT_TCL_VARIABLE
  SQLITE_OMIT_TRACE
  SQLITE_USE_ALLOCA
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_ENABLE_DBSTAT_VTAB
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_JSON1
  SQLITE_ENABLE_RTREE
)

# Ensure sqlite3 actually gets build
add_dependencies(${PLUGIN_NAME} sqlite3)

# List of absolute paths to libraries that should be bundled with the plugin
set(sqlcipher_flutter_libs_bundled_libraries
  "$<TARGET_FILE:sqlite3>"
  PARENT_SCOPE
)
