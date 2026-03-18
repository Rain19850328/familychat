import fs from "node:fs";
import path from "node:path";

const rootDir = process.cwd();
const requireConfig = process.argv.includes("--require-config");
const failures = [];
const warnings = [];

function readFile(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function assertFileExists(relativePath) {
  const absolutePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(absolutePath)) {
    failures.push(`Missing file: ${relativePath}`);
  }
}

function verifySyntax(relativePath, transform = (source) => source) {
  try {
    const source = transform(readFile(relativePath));
    new Function(source);
  } catch (error) {
    failures.push(`Syntax check failed for ${relativePath}: ${error.message}`);
  }
}

function checkHtmlAssets() {
  const html = readFile("index.html");
  const assetMatches = html.matchAll(/(?:src|href)="([^"]+)"/g);

  for (const match of assetMatches) {
    const assetPath = match[1];
    if (/^(https?:|data:|#)/.test(assetPath)) {
      continue;
    }

    const normalized = assetPath.replace(/^\.\//, "");
    assertFileExists(normalized);
  }
}

function checkServiceWorkerAssets() {
  const source = readFile("service-worker.js");
  const shellMatch = source.match(/const APP_SHELL = \[([\s\S]*?)\];/);
  if (!shellMatch) {
    failures.push("Could not parse APP_SHELL from service-worker.js");
    return;
  }

  const assetMatches = shellMatch[1].matchAll(/"([^"]+)"/g);
  for (const match of assetMatches) {
    const assetPath = match[1];
    if (assetPath === "./") {
      continue;
    }

    const normalized = assetPath.replace(/^\.\//, "");
    assertFileExists(normalized);
  }
}

function checkSupabaseConfig() {
  const configSource = readFile("supabase.config.js");
  const hasPlaceholderUrl = configSource.includes("YOUR_PROJECT_REF");
  const hasPlaceholderKey = configSource.includes("YOUR_SUPABASE_ANON_KEY");

  if (hasPlaceholderUrl || hasPlaceholderKey) {
    const message = "supabase.config.js still contains placeholder Supabase values.";
    if (requireConfig) {
      failures.push(message);
    } else {
      warnings.push(message);
    }
  }
}

[
  "index.html",
  "app.js",
  "service-worker.js",
  "styles.css",
  "manifest.webmanifest",
  "supabase.config.js",
  "supabase/migrations/20260317130258_remote_schema.sql",
].forEach(assertFileExists);

checkHtmlAssets();
checkServiceWorkerAssets();
checkSupabaseConfig();

verifySyntax("supabase.config.js");
verifySyntax("service-worker.js");
verifySyntax("app.js", (source) => source.replace(/^import .*$/m, ""));

for (const warning of warnings) {
  console.warn(`WARN: ${warning}`);
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`FAIL: ${failure}`);
  }
  process.exitCode = 1;
} else {
  console.log("OK: deployment verification passed");
}
