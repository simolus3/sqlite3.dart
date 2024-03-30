use std::{env, path::PathBuf};

fn main() {
    let bindings = bindgen::Builder::default()
        .header("../../.dart_tool/sqlite3_build/_deps/sqlite3-src/sqlite3.h")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .use_core()
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());

    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
