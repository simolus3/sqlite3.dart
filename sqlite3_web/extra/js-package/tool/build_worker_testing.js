import { mkdirSync, rmSync } from "fs";
import { spawnSync } from "child_process";
import { fileURLToPath } from "url";
import { resolve, dirname } from "path";

const toolDir = dirname(fileURLToPath(import.meta.url));
const assetsDir = resolve(toolDir, "../assets");

mkdirSync(assetsDir, { recursive: true });

const result = spawnSync(
  "dart",
  [
    "compile",
    "js",
    "-O4",
    "-Dsqlite3.dartbigints=false",
    "-Dsqlite3web.testing=true",
    resolve(toolDir, "worker.dart"),
    "--no-source-maps",
    "--no-minify",
    "-m",
    "-o",
    resolve(assetsDir, "worker_testing.js"),
  ],
  { stdio: "inherit" },
);

rmSync(resolve(assetsDir, "worker_testing.js.deps"));

if (result.status) {
  process.exit(result.status);
}
