INSERT IGNORE INTO schemaversion (versionnumber) values ("quick-entry-patch");

-- Add missing columns to the omoccurrences table where the quick entry data is stored.
-- Guarded per-column ADD so re-runs are idempotent on MySQL 5.7 AND 8.0
-- (MySQL has no ADD COLUMN IF NOT EXISTS; use information_schema + prepared stmt, no DELIMITER/proc).
-- NOTE: `herbarium varchar(4) NOT NULL` is given DEFAULT '' so the ADD COLUMN does not
-- fail on an already-populated omoccurrences table under STRICT_TRANS_TABLES (MySQL 5.7+).

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='filedUnder');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `filedUnder` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='geoWithin');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `geoWithin` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='herbarium');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `herbarium` varchar(4) NOT NULL DEFAULT ''");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='accesNum');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `accesNum` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='currName');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `currName` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='idQualifier');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `idQualifier` varchar(16) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='detText');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `detText` text DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='provenance');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `provenance` text DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='container');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `container` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='collTrip');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `collTrip` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='highGeo');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `highGeo` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='frequency');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `frequency` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='prepMethod');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `prepMethod` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='format');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `format` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='verbLat');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `verbLat` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='verbLong');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `verbLong` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='method');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `method` varchar(255) DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
