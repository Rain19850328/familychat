import fs from "node:fs";
import path from "node:path";

const rootDir = process.cwd();
const distDir = path.join(rootDir, "dist");
const filesToCopy = [
  "index.html",
  "app.js",
  "styles.css",
  "manifest.webmanifest",
  "service-worker.js",
  "supabase.config.js",
];
const directoriesToCopy = ["icons"];

fs.rmSync(distDir, { recursive: true, force: true });
fs.mkdirSync(distDir, { recursive: true });

for (const file of filesToCopy) {
  fs.copyFileSync(path.join(rootDir, file), path.join(distDir, file));
}

for (const directory of directoriesToCopy) {
  fs.cpSync(path.join(rootDir, directory), path.join(distDir, directory), {
    recursive: true,
  });
}

console.log(`Prepared static artifact in ${distDir}`);
