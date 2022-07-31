cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlite3_flutter_libs")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "sqlite3_flutter_libs_plugin")

include(FetchContent)
FetchContent_Declare(
  sqlite3
  URL https://www.sqlite.org/2022/sqlite-autoconf-3390200.tar.gz
)
FetchContent_MakeAvailable(sqlite3)

FetchContent_Declare(
  spellfix1
  URL https://raw.githubusercontent.com/sqlite/sqlite/branch-3.39/ext/misc/spellfix.c
  DOWNLOAD_NO_EXTRACT TRUE
)
FetchContent_MakeAvailable(spellfix1)

add_library(${PLUGIN_NAME} SHARED
  "sqlite3_flutter_libs_plugin.cc"
  "${sqlite3_SOURCE_DIR}/sqlite3.c"
  "${spellfix1_SOURCE_DIR}/spellfix.c"
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
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

# Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
target_compile_definitions(${PLUGIN_NAME} PRIVATE
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
