SQLITE_API char* sqlite3_dart_temp_directory(int set, char* update) {
    if (set) {
        sqlite3_temp_directory = update;
    }
    return sqlite3_temp_directory;
}
