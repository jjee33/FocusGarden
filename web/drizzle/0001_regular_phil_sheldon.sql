CREATE TABLE `mail_throttle` (
	`key` text PRIMARY KEY NOT NULL,
	`last_sent_at` integer NOT NULL,
	`window_start` integer NOT NULL,
	`count` integer NOT NULL
);
