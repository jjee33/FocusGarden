import { spawnSync } from "node:child_process";

// Node 25+ installs an experimental global localStorage getter that is
// undefined without --localstorage-file; it masks jsdom's storage in Vitest.
const nodeMajor = Number(process.versions.node.split(".")[0]);
const nodeFlags = nodeMajor >= 25 ? ["--no-experimental-webstorage"] : [];
const result = spawnSync(process.execPath, [...nodeFlags, "node_modules/vitest/vitest.mjs", "run", ...process.argv.slice(2)], {
  stdio: "inherit",
  env: {
    ...process.env,
    NODE_OPTIONS: [process.env.NODE_OPTIONS, ...nodeFlags].filter(Boolean).join(" "),
  },
});
if (result.error) {
  console.error(result.error);
  process.exit(1);
}
if (result.signal) {
  process.kill(process.pid, result.signal);
} else {
  process.exit(result.status ?? 1);
}
