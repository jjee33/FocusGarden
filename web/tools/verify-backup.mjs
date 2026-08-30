/**
 * Proves a backup can actually be restored.
 *
 *     node --no-warnings tools/verify-backup.mjs <file.sql>
 *
 * A backup nobody has restored is a file, not a backup. This loads the dump into
 * a throwaway SQLite database - the same engine D1 runs - and reports what came
 * back. If it will not load here it will not load anywhere, and finding that out
 * on the day you need it is the entire failure mode backups exist to prevent.
 *
 * Deliberately does NOT touch D1. Restoring into the live database to check a
 * backup is how a verification step becomes an outage.
 */

import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

const file = process.argv[2];
if (file === undefined) {
  console.error("Usage: node --no-warnings tools/verify-backup.mjs <file.sql>");
  process.exit(2);
}

const sql = readFileSync(file, "utf8");
const db = new DatabaseSync(":memory:");

/*
 * FOREIGN KEYS OFF WHILE LOADING, THEN CHECKED PROPERLY.
 *
 * D1 writes the dump alphabetically by table, so `INSERT INTO account` runs long
 * before `CREATE TABLE user` exists. Its own mitigation is the
 * `PRAGMA defer_foreign_keys=TRUE` at the top of the file - but that only defers
 * to the end of a TRANSACTION, and a plain exec is not one, so the first insert
 * fails with "no such table: main.user".
 *
 * Turning enforcement off for the load and then running foreign_key_check is
 * strictly better than deferring: the dump loads regardless of table order, and
 * every reference is verified afterwards rather than merely at the moment it was
 * written. A backup that restores but has dangling references is not a backup
 * either, and nothing else would have caught that.
 */
db.exec("PRAGMA foreign_keys=OFF;");
try {
  db.exec(sql);
} catch (error) {
  console.error(`RESTORE FAILED: ${error.message}`);
  process.exit(1);
}

const violations = db.prepare("PRAGMA foreign_key_check").all();
if (violations.length > 0) {
  console.error(`RESTORED, BUT ${violations.length} dangling reference(s):`);
  for (const v of violations.slice(0, 5)) console.error(`  ${JSON.stringify(v)}`);
  process.exit(1);
}

const tables = db
  .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
  .all()
  .map((r) => r.name);

let total = 0;
const counts = tables.map((t) => {
  // Identifier, not a value, so it cannot be bound - the names come from
  // sqlite_master in a database we just built from the file being checked.
  const n = db.prepare(`SELECT COUNT(*) AS n FROM "${t}"`).get().n;
  total += n;
  return { table: t, rows: n };
});

console.log(`Restored ${file}`);
console.log(`  ${tables.length} tables, ${total} rows`);
for (const c of counts.filter((c) => c.rows > 0)) {
  console.log(`    ${c.table.padEnd(20)} ${c.rows}`);
}

// The point of the exercise: is the thing people would actually miss in there?
const users = counts.find((c) => c.table === "user")?.rows ?? 0;
if (users === 0) {
  console.error("  WARNING: no user rows. Schema restored, but there is no account data in this backup.");
  process.exit(1);
}
console.log(`  ${users} account(s) recoverable.`);
db.close();
