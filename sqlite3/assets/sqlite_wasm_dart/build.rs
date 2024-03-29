fn main() {
    let mut cfg = cc::Build::new();
    cfg.compiler("clang");
    cfg.flag("--sysroot").flag("/usr/share/wasi-sysroot");

    // Compile the SQLite source
    cfg.file("sqlite3/sqlite3.c");
    cfg.include("sqlite3/");
    cfg.compile("sqlite3");
}
