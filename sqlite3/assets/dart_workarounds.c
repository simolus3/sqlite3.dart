SQLITE_API char* sqlite3_dart_temp_directory(int set, char* update) {
    if (set) {
        sqlite3_temp_directory = update;
    }
    return sqlite3_temp_directory;
}

SQLITE_API int sqlite3_dart_db_config(sqlite3* db, int op, int a, int* b) {
    return sqlite3_db_config(db, op, a, b);
}
