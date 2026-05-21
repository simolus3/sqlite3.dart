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
    resolve(toolDir, "worker.dart"),
    "--no-source-maps",
    "-m",
    "-o",
    resolve(assetsDir, "worker.js"),
  ],
  { stdio: "inherit" },
);

rmSync(resolve(assetsDir, "worker.js.deps"));

if (result.status) {
  process.exit(result.status);
}
