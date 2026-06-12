INSERT IGNORE INTO schemaversion (versionnumber) values ("ai-transcription-patch");
-- NOTE: These tables are not currently in use by the frontend, but the frontend should be updated to use these tables for the ai transcription feature
-- NOTE: ocr_results FKs the `batch` table, now created by db_schema_patch-batch-core.sql.
-- Apply batch-core FIRST: this feature is applied as (batch-core + ai-transcription).
-- No DROP TABLE here, and CREATE uses IF NOT EXISTS, so re-running never wipes data.

-- Create ocr_results table
CREATE TABLE IF NOT EXISTS `ocr_results` (
  `imgid` int(10) unsigned NOT NULL,
  `batchID` int(11) NOT NULL,
  `collID` int(11) NOT NULL,
  `results` JSON NOT NULL,
  `processed_date` timestamp NOT NULL,
  PRIMARY KEY (`imgid`,`batchID`),
  KEY `FK_ocr_results_img` (`imgid`),
  KEY `FK_ocr_results_batch` (`batchID`),
  CONSTRAINT `FK_ocr_results_img` FOREIGN KEY (`imgid`) REFERENCES `images` (`imgid`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_ocr_results_batch` FOREIGN KEY (`batchID`) REFERENCES `batch` (`batchID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Add columns to the omoccurrences to indicate whether the record was human or machine generated and its confidence value (if machine generated)
-- Guarded per-column ADD so re-runs are idempotent on MySQL 5.7 AND 8.0
-- (MySQL has no ADD COLUMN IF NOT EXISTS; use information_schema + prepared stmt, no DELIMITER/proc).
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='is_machine_generated');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `is_machine_generated` BOOL DEFAULT 0");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='omoccurrences' AND COLUMN_NAME='confidence_value');
SET @s := IF(@c>0,'SELECT 1',"ALTER TABLE `omoccurrences` ADD COLUMN `confidence_value` double DEFAULT NULL");
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
