INSERT IGNORE INTO schemaversion (versionnumber) values ("batch-core-patch");

-- Core `batch` table, shared by the image-batching and ai-transcription features.
-- Split out of db_schema_patch-image-batching.sql so that any feature whose tables
-- FK to `batch` (image-batching's batch_XREF/batch_user, ai-transcription's
-- ocr_results) can be applied as (batch-core + that feature). Apply this FIRST.
-- IF NOT EXISTS makes re-runs safe; this patch never drops the table.
CREATE TABLE IF NOT EXISTS `batch` (
  `batchID` int(11) NOT NULL AUTO_INCREMENT,
  `ingest_date` timestamp NOT NULL,
  `completed_date` timestamp NULL,
  `batch_name` varchar(100) NOT NULL,
  `image_batch_path` varchar(100) NOT NULL,
  `initialtimestamp` TIMESTAMP NULL DEFAULT current_timestamp,
  `last_edited` int(11) NULL,
  `collID` int(11) NOT NULL,
  PRIMARY KEY (`batchID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
