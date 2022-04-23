cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlcipher_flutter_libs")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "sqlcipher_flutter_libs_plugin")

include(FetchContent)
FetchContent_Declare(
  sqlcipher
  GIT_REPOSITORY https://github.com/sqlcipher/sqlcipher.git
  GIT_TAG v4.5.1
)
FetchContent_MakeAvailable(sqlcipher)

set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)

add_custom_command(
  OUTPUT "${sqlcipher_SOURCE_DIR}/Makefile"
  COMMAND ./configure
  WORKING_DIRECTORY "${sqlcipher_SOURCE_DIR}"
)

add_custom_command(
  OUTPUT "${sqlcipher_SOURCE_DIR}/sqlite3.c"
  OUTPUT "${sqlcipher_SOURCE_DIR}/sqlite3.h"
  DEPENDS "${sqlcipher_SOURCE_DIR}/Makefile"
  COMMAND make sqlite3.c sqlite3.h
  WORKING_DIRECTORY "${sqlcipher_SOURCE_DIR}"
)

add_library(${PLUGIN_NAME} SHARED
  "sqlite3_flutter_libs_plugin.cc"
  "${sqlcipher_SOURCE_DIR}/sqlite3.c"
)

# Not applying the standard settings because we compile sqlite3
# which fails with -Wall -Werror. But we apply most of them:
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_14)
target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter OpenSSL::Crypto)

# Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
# SQLITE_HAS_CODEC is required for sqlcipher
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  SQLITE_HAS_CODEC
  SQLITE_DQS=0
  SQLITE_THREADSAFE=2
  SQLITE_DEFAULT_MEMSTATUS=0
  SQLITE_TEMP_STORE=2
  SQLITE_MAX_EXPR_DEPTH=0
  SQLITE_OMIT_AUTHORIZATION
  SQLITE_OMIT_DECLTYPE
  SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_GET_TABLE
  SQLITE_OMIT_LOAD_EXTENSION
  SQLITE_OMIT_PROGRESS_CALLBACK
  SQLITE_OMIT_SHARED_CACHE
  SQLITE_OMIT_TCL_VARIABLE
  SQLITE_OMIT_TRACE
  SQLITE_USE_ALLOCA
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_JSON1
  SQLITE_ENABLE_RTREE
)