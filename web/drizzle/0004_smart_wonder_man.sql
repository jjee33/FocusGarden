PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_achievement_state` (
	`id` text NOT NULL,
	`user_id` text NOT NULL,
	`data` text NOT NULL,
	`revision` integer DEFAULT 1 NOT NULL,
	`updated_at` integer NOT NULL,
	`deleted_at` integer,
	PRIMARY KEY(`user_id`, `id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_achievement_state`("id", "user_id", "data", "revision", "updated_at", "deleted_at") SELECT "id", "user_id", "data", "revision", "updated_at", "deleted_at" FROM `achievement_state`;--> statement-breakpoint
DROP TABLE `achievement_state`;--> statement-breakpoint
ALTER TABLE `__new_achievement_state` RENAME TO `achievement_state`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE INDEX `achievement_state_user_idx` ON `achievement_state` (`user_id`,`revision`);--> statement-breakpoint
CREATE TABLE `__new_catalogue_entry` (
	`id` text NOT NULL,
	`user_id` text NOT NULL,
	`data` text NOT NULL,
	`revision` integer DEFAULT 1 NOT NULL,
	`updated_at` integer NOT NULL,
	`deleted_at` integer,
	PRIMARY KEY(`user_id`, `id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_catalogue_entry`("id", "user_id", "data", "revision", "updated_at", "deleted_at") SELECT "id", "user_id", "data", "revision", "updated_at", "deleted_at" FROM `catalogue_entry`;--> statement-breakpoint
DROP TABLE `catalogue_entry`;--> statement-breakpoint
ALTER TABLE `__new_catalogue_entry` RENAME TO `catalogue_entry`;--> statement-breakpoint
CREATE INDEX `catalogue_entry_user_idx` ON `catalogue_entry` (`user_id`,`revision`);--> statement-breakpoint
CREATE TABLE `__new_focus_session` (
	`id` text NOT NULL,
	`user_id` text NOT NULL,
	`date_key` text NOT NULL,
	`data` text NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`user_id`, `id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_focus_session`("id", "user_id", "date_key", "data", "created_at") SELECT "id", "user_id", "date_key", "data", "created_at" FROM `focus_session`;--> statement-breakpoint
DROP TABLE `focus_session`;--> statement-breakpoint
ALTER TABLE `__new_focus_session` RENAME TO `focus_session`;--> statement-breakpoint
CREATE INDEX `focus_session_user_date_idx` ON `focus_session` (`user_id`,`date_key`);--> statement-breakpoint
CREATE INDEX `focus_session_user_created_idx` ON `focus_session` (`user_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `__new_journal_entry` (
	`id` text NOT NULL,
	`user_id` text NOT NULL,
	`data` text NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`user_id`, `id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_journal_entry`("id", "user_id", "data", "created_at") SELECT "id", "user_id", "data", "created_at" FROM `journal_entry`;--> statement-breakpoint
DROP TABLE `journal_entry`;--> statement-breakpoint
ALTER TABLE `__new_journal_entry` RENAME TO `journal_entry`;--> statement-breakpoint
CREATE INDEX `journal_user_idx` ON `journal_entry` (`user_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `__new_plant` (
	`id` text NOT NULL,
	`user_id` text NOT NULL,
	`data` text NOT NULL,
	`revision` integer DEFAULT 1 NOT NULL,
	`updated_at` integer NOT NULL,
	`deleted_at` integer,
	PRIMARY KEY(`user_id`, `id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_plant`("id", "user_id", "data", "revision", "updated_at", "deleted_at") SELECT "id", "user_id", "data", "revision", "updated_at", "deleted_at" FROM `plant`;--> statement-breakpoint
DROP TABLE `plant`;--> statement-breakpoint
ALTER TABLE `__new_plant` RENAME TO `plant`;--> statement-breakpoint
CREATE INDEX `plant_user_idx` ON `plant` (`user_id`,`revision`);--> statement-breakpoint
CREATE TABLE `__new_project` (
	`id` text NOT NULL,
	`user_id` text NOT NULL,
	`data` text NOT NULL,
	`revision` integer DEFAULT 1 NOT NULL,
	`updated_at` integer NOT NULL,
	`deleted_at` integer,
	PRIMARY KEY(`user_id`, `id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_project`("id", "user_id", "data", "revision", "updated_at", "deleted_at") SELECT "id", "user_id", "data", "revision", "updated_at", "deleted_at" FROM `project`;--> statement-breakpoint
DROP TABLE `project`;--> statement-breakpoint
ALTER TABLE `__new_project` RENAME TO `project`;--> statement-breakpoint
CREATE INDEX `project_user_idx` ON `project` (`user_id`,`revision`);