import { mkdirSync } from "fs";
import { writeFile } from "fs/promises";
import { fileURLToPath } from "url";
import { resolve, dirname } from "path";

const toolDir = dirname(fileURLToPath(import.meta.url));
const assetsDir = resolve(toolDir, "../assets");

mkdirSync(assetsDir, { recursive: true });

const response = await fetch(
  "https://api.github.com/repos/simolus3/sqlite3.dart/releases/latest",
);
if (!response.ok) {
  throw new Error(`Failed to fetch release info: ${response.status}`);
}

const release = await response.json();

await Promise.all(
  ["sqlite3.wasm", "sqlite3mc.wasm"].map(async (name) => {
    const asset = release.assets.find((a) => a.name === name);
    if (!asset)
      throw new Error(`${name} not found in release ${release.tag_name}`);

    const download = await fetch(asset.browser_download_url);
    if (!download.ok) {
      throw new Error(`Failed to download ${name}: ${download.status}`);
    }

    await writeFile(
      resolve(assetsDir, name),
      Buffer.from(await download.arrayBuffer()),
    );
    console.log(`Downloaded ${name} (${release.tag_name})`);
  }),
);
