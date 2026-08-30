/**
 * Nightly backup of the production database, with retention and verification.
 *
 * Cloudflare replicates D1 but does not keep a copy you control, and "the
 * provider has it" is not a backup: it does not survive a bad migration, a
 * mistaken DELETE, or an account problem. This produces a file on hardware you
 * own.
 *
 *     node tools/backup-d1.mjs [--dir <path>] [--keep-daily 7] [--dry-run]
 *
 * Runs anywhere with Node and an authenticated wrangler - a Proxmox LXC, a NAS,
 * a desktop on a schedule. It is deliberately pull-based: nothing inbound has to
 * be opened at home, and the machine holding the backups never has to be
 * reachable from the internet.
 *
 * A NOTE ON THE OUTPUT OF `wrangler d1 export`. It prints a signed R2 URL that
 * grants anyone holding it an hour of access to the complete database dump.
 * That is fine on a private terminal and is a credential leak in a CI log or a
 * shared session, so this filters wrangler's stdout rather than echoing it.
 *
 * EVERY BACKUP IS VERIFIED BEFORE IT COUNTS. A dump that was written but is
 * truncated, empty, or missing tables is worse than a missing one, because it
 * satisfies every check that only asks whether a file exists.
 */

import { execFile } from "node:child_process";
import { DatabaseSync } from "node:sqlite";
import { mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, renameSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

const DATABASE = "focus-garden";

/** Tables the dump must contain, or something went wrong upstream of the file. */
const REQUIRED_TABLES = [
  "user", "session", "account", "verification",
  "profile", "plant", "project", "catalogue_entry", "achievement_state",
  "journal_entry", "focus_session", "daily_rollup", "revision_counter",
  "push_log", "mail_throttle",
];

/** Grandfather-father-son. Enough history to survive a fault noticed late. */
const RETENTION = { daily: 7, weekly: 4, monthly: 12 };

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}
const DRY_RUN = process.argv.includes("--dry-run");
const DIR = arg("dir", "backups");

function stamp(d) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`
    + `T${p(d.getUTCHours())}${p(d.getUTCMinutes())}Z`;
}

/**
 * Actually restores the dump and decides whether it is a real backup.
 *
 * NOT a text inspection. Grepping for CREATE TABLE proves the file mentions the
 * right words; it does not prove SQLite will accept it, and the difference is
 * the whole point of having backups. This loads it into a throwaway in-memory
 * database - the same engine D1 runs - and reports what came back.
 *
 * Foreign keys are off during the load because D1 writes the dump alphabetically
 * by table, so `INSERT INTO account` arrives long before `CREATE TABLE user`
 * exists. The `PRAGMA defer_foreign_keys=TRUE` at the top of the file only
 * defers to the end of a TRANSACTION, which a plain load is not. Enforcement is
 * then verified explicitly with foreign_key_check, which is stronger: a backup
 * that restores but carries dangling references is not one either.
 */
function verify(path) {
  const sql = readFileSync(path, "utf8");
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("PRAGMA foreign_keys=OFF;");
    db.exec(sql);

    const dangling = db.prepare("PRAGMA foreign_key_check").all();
    const tables = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
      .all().map((r) => r.name);
    const missing = REQUIRED_TABLES.filter((t) => !tables.includes(t));

    let rows = 0;
    for (const t of tables) rows += db.prepare(`SELECT COUNT(*) AS n FROM "${t}"`).get().n;
    const users = tables.includes("user")
      ? db.prepare("SELECT COUNT(*) AS n FROM user").get().n
      : 0;

    return {
      // A schema-only dump of a wiped database is valid SQL and is exactly the
      // thing that must not be kept while good copies are rotated away.
      ok: missing.length === 0 && dangling.length === 0 && users > 0,
      bytes: sql.length, tables: tables.length, rows, users,
      missing, dangling: dangling.length, error: "",
    };
  } catch (error) {
    return {
      ok: false, bytes: sql.length, tables: 0, rows: 0, users: 0,
      missing: [], dangling: 0, error: error.message,
    };
  } finally {
    db.close();
  }
}

/** Which dated files to keep: the newest N days, then one a week, then one a month. */
export function planRetention(names, now, keep = RETENTION) {
  const dated = names
    .map((n) => ({ n, m: /^focus-garden-(\d{4})-(\d{2})-(\d{2})T/.exec(n) }))
    .filter((x) => x.m !== null)
    .map((x) => ({ n: x.n, d: new Date(Date.UTC(+x.m[1], +x.m[2] - 1, +x.m[3])) }))
    .sort((a, b) => b.d.getTime() - a.d.getTime());

  const kept = new Set();
  const day = 86400000;

  for (const f of dated.slice(0, keep.daily)) kept.add(f.n);

  // One per ISO week and one per month, walking newest first so the survivor of
  // each period is its most recent - a backup taken later in a week has strictly
  // more history in it.
  const seenWeek = new Set();
  const seenMonth = new Set();
  for (const f of dated) {
    const week = Math.floor(f.d.getTime() / (7 * day));
    const month = `${f.d.getUTCFullYear()}-${f.d.getUTCMonth()}`;
    if (!seenWeek.has(week) && seenWeek.size < keep.weekly) { seenWeek.add(week); kept.add(f.n); }
    if (!seenMonth.has(month) && seenMonth.size < keep.monthly) { seenMonth.add(month); kept.add(f.n); }
  }

  void now;
  return { keep: [...kept], drop: dated.filter((f) => !kept.has(f.n)).map((f) => f.n) };
}

async function main() {
  mkdirSync(DIR, { recursive: true });

  const name = `focus-garden-${stamp(new Date())}.sql`;
  const finalPath = join(DIR, name);
  // Written under a temporary name and renamed only once verified, so a failed
  // or partial run never leaves something that looks like a good backup.
  const tempPath = `${finalPath}.partial`;

  console.log(`Exporting ${DATABASE}…`);
  try {
    await run("npx", ["wrangler", "d1", "export", DATABASE, "--remote", "--output", tempPath], {
      shell: true,
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (error) {
    // The message can carry the signed URL; report the failure without it.
    console.error("Export failed. wrangler exited non-zero.");
    console.error(String(error.code ?? error.message).slice(0, 200));
    process.exit(1);
  }

  console.log("Restoring it into a scratch database to check it…");
  const check = verify(tempPath);
  if (!check.ok) {
    console.error("REJECTED. This file is not a usable backup:");
    if (check.error !== "") console.error(`  would not restore: ${check.error}`);
    if (check.missing.length > 0) console.error(`  missing tables: ${check.missing.join(", ")}`);
    if (check.dangling > 0) console.error(`  ${check.dangling} dangling foreign key reference(s)`);
    if (check.users === 0) console.error("  no user rows - schema only, no account data");
    console.error("Kept as .partial for inspection and NOT rotated in.");
    process.exit(1);
  }

  renameSync(tempPath, finalPath);
  console.log(`OK  ${name}`);
  console.log(`    ${check.bytes} bytes, ${check.tables} tables, ${check.rows} rows, ${check.users} account(s) recoverable`);

  const existing = readdirSync(DIR).filter((f) => f.endsWith(".sql"));
  const { keep, drop } = planRetention(existing, new Date());
  console.log(`Retention: keeping ${keep.length}, removing ${drop.length}`);
  for (const f of drop) {
    if (DRY_RUN) { console.log(`  would remove ${f}`); continue; }
    unlinkSync(join(DIR, f));
    console.log(`  removed ${f}`);
  }

  const total = readdirSync(DIR)
    .filter((f) => f.endsWith(".sql"))
    .reduce((sum, f) => sum + statSync(join(DIR, f)).size, 0);
  console.log(`${DIR}: ${(total / 1024).toFixed(0)} kB across ${keep.length} backups.`);
}

// Importable for tests without running a backup.
if (process.argv[1]?.endsWith("backup-d1.mjs")) await main();
