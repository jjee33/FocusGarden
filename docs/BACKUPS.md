# Backups

Cloudflare replicates D1, and that is not a backup. Replication faithfully copies
a bad migration, a mistaken `DELETE`, and an account suspension. A backup is a
copy **you** hold, on hardware **you** control, that you have proved you can
restore.

Two tools, both in `web/tools/`:

| | |
|---|---|
| `backup-d1.mjs` | Export, verify by restoring, rotate. This is the one you schedule. |
| `verify-backup.mjs` | Restore any single file and report what came back. Run it by hand when you want to be sure. |

---

## Taking a backup

```bash
node --no-warnings web/tools/backup-d1.mjs --dir /srv/focusgarden/backups
```

It exports the live database, **restores the dump into a throwaway in-memory
SQLite database**, and only keeps the file if that worked. Then it rotates.

Exit code is 0 only when a usable backup was written. Anything else is non-zero,
which is what makes it safe to schedule.

### Why it restores every time

Checking that a file exists proves nothing. Checking that it contains the string
`CREATE TABLE` proves it mentions the right words. Neither tells you whether
SQLite will accept it, and that difference is the entire reason backups exist.

Four things are rejected, all of them tested:

- a dump that will not parse (truncated mid-statement, or not SQL at all)
- a dump missing any expected table
- a dump with dangling foreign key references
- **a schema-only dump with no user rows** — valid SQL, restores perfectly, and
  is exactly what a wiped database produces. Keeping one of these while rotating
  away the good copies is the worst outcome available.

A rejected file is left as `.partial` for inspection and is never rotated in.

### A wrinkle worth knowing

D1 writes the dump alphabetically by table, so `INSERT INTO account` appears long
before `CREATE TABLE user`. The `PRAGMA defer_foreign_keys=TRUE` at the top only
defers to the end of a *transaction*, so a naive load fails on the first insert
with `no such table: main.user`. Both tools load with foreign keys off and then
run `PRAGMA foreign_key_check`, which is stronger than deferring: every reference
is verified rather than merely tolerated.

### Also worth knowing

`wrangler d1 export` prints a signed R2 URL that grants **an hour of access to
the complete database dump** to anyone holding it. Fine on a private terminal, a
credential leak in a CI log or a shared session. `backup-d1.mjs` does not echo
wrangler's output for that reason. Bear it in mind before piping any of this
somewhere it will be recorded.

---

## Retention

Grandfather-father-son: the last 7 days, then one per week for 4 weeks, then one
per month for 12 months. Roughly 20 files, about 25 kB each today.

The shape matters more than the numbers. Daily copies catch "I broke it an hour
ago"; monthly copies catch "this has been quietly wrong since June", which is the
failure that actually loses data, because nobody notices it the same week.

Anything in the directory that is not a `focus-garden-<date>T<time>Z.sql` file is
left alone. Adjust with `--keep-daily`, or preview with `--dry-run`.

---

## Where to run it

Anywhere with Node 22+, an authenticated `wrangler`, and disk. It is
**pull-based**: the machine holding the backups reaches out, so nothing inbound
has to be opened at home and that machine never needs to be reachable from the
internet.

### On the Proxmox node

A Debian LXC with Node and wrangler, backups on a ZFS dataset so snapshots and
scrub give a second layer under the files themselves.

```
0 3 * * *  cd /srv/focusgarden && node --no-warnings web/tools/backup-d1.mjs --dir /srv/focusgarden/backups >> /var/log/fg-backup.log 2>&1
```

Wrangler needs credentials in that container — a scoped API token with **D1
read** is enough, and is a great deal better than a full-access OAuth login
sitting on a machine that runs unattended.

### On a desktop

Task Scheduler or `cron` with the same command. Less durable than the node, and
enormously better than nothing.

---

## Restoring

```bash
node --no-warnings web/tools/verify-backup.mjs backups/focus-garden-2026-08-30T0300Z.sql
```

That proves the file is good without touching anything live. To actually restore
into a database:

```bash
npx wrangler d1 execute focus-garden --remote --file backups/focus-garden-....sql
```

**Restore into a scratch database first.** Create one, restore, look at it, and
only then decide what to do with production. A restore aimed at the live database
during an incident is how one bad hour becomes a bad week.

---

## The check nobody does

Once a quarter, restore the *oldest* backup you still keep and count the rows.
The automated verification runs on fresh dumps; it says nothing about whether a
ten-month-old file on a disk you have not touched since is still readable. That
is the copy you will want on the day it matters.
