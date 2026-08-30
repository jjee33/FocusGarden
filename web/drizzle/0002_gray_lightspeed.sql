-- Adds the `issuer` column better-auth 1.7 requires on `account`.
--
-- ADD COLUMN ... NOT NULL with no default fails on a table that has rows, and
-- there is no backfill here because there cannot be one: `account` is empty in
-- both the local and the remote database, verified before writing this. That is
-- not luck - the missing column is exactly what made every sign-up throw after
-- creating the user row and before writing the credential, so no account row has
-- ever been written. A DEFAULT would have been the safe habit, but it would also
-- stay on the column forever and read as schema drift on every later generate.
ALTER TABLE `account` ADD `issuer` text NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `account_issuer_account_id` ON `account` (`issuer`,`account_id`);--> statement-breakpoint
CREATE INDEX `account_user_id` ON `account` (`user_id`);