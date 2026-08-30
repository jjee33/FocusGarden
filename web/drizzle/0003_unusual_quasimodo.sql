CREATE TABLE `device_token` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`token_hash` text NOT NULL,
	`label` text NOT NULL,
	`created_at` integer NOT NULL,
	`last_used_at` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `device_token_token_hash_unique` ON `device_token` (`token_hash`);--> statement-breakpoint
CREATE INDEX `device_token_user` ON `device_token` (`user_id`);