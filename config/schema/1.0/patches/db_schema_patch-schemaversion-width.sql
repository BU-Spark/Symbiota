-- Widen schemaversion.versionnumber, and repair names already truncated by it.
--
-- schemaversion.versionnumber is varchar(20) (config/schema/3.0/db_schema-3.0.sql:2718)
-- with a UNIQUE key (:2721). Upstream never hits that limit -- every upstream
-- version string is "N.N". This fork records descriptive patch names, and three
-- of them are longer than 20 characters:
--
--   ai-transcription-patch       22  ->  stored as 'ai-transcription-pat'
--   batch-ingestion-patch        21  ->  stored as 'batch-ingestion-patc'
--   portal-mysql57-compat-patch  27  ->  stored as 'portal-mysql57-compa'
--   image-batching-patch         20      fits, but with zero headroom
--
-- Those INSERTs all use INSERT IGNORE, and IGNORE downgrades MySQL 8's
-- strict-mode "Data too long" error to a warning plus silent truncation. So the
-- statement appears to succeed, the patch reports clean, and the recorded name
-- is wrong. Confirmed on the live int and alpha databases: both hold
-- 'ai-transcription-pat'.
--
-- Two consequences:
--
--   Idempotency is broken. Any "has this patch been applied?" check queries the
--   full 22-character name and finds nothing, because 20 characters were stored,
--   so the patch looks unapplied forever and is reapplied on every run.
--
--   A future collision is silent and permanent. Two patch names sharing their
--   first 20 characters truncate to the same value; the second hits
--   versionnumber_UNIQUE, INSERT IGNORE swallows it, and that patch is recorded
--   as applied without ever running. image-batching-patch is already exactly at
--   the limit, so anything like image-batching-patch-v2 collides immediately.
--
-- ORDERING: this must run BEFORE the feature patches whose names truncate, or
-- they simply truncate again. It is registered ahead of them in
-- containers/scripts/bootstrap-symbiota.sh.
--
-- Existing deployments (int, alpha) need this applied by hand -- bootstrap is a
-- fresh-install script and will not revisit them.
--
-- Idempotent: safe on a fresh database, an already-widened one, or one that has
-- been hand-repaired.

ALTER TABLE `schemaversion` MODIFY `versionnumber` varchar(64) NOT NULL;

-- Repair rows recorded before the widening.
--
-- Two statements per name, in this order, so versionnumber_UNIQUE can never be
-- violated:
--   1. DELETE the truncated row, but only if a correct full-length row already
--      exists (self-join -- a no-op when it does not).
--   2. Rename whatever truncated row remains.
--
-- Renaming rather than insert-then-delete preserves the original dateapplied,
-- which is the only record of when the patch actually ran.

DELETE s FROM `schemaversion` s
  JOIN `schemaversion` f ON f.`versionnumber` = 'ai-transcription-patch'
  WHERE s.`versionnumber` = 'ai-transcription-pat';
UPDATE `schemaversion` SET `versionnumber` = 'ai-transcription-patch'
  WHERE `versionnumber` = 'ai-transcription-pat';

DELETE s FROM `schemaversion` s
  JOIN `schemaversion` f ON f.`versionnumber` = 'batch-ingestion-patch'
  WHERE s.`versionnumber` = 'batch-ingestion-patc';
UPDATE `schemaversion` SET `versionnumber` = 'batch-ingestion-patch'
  WHERE `versionnumber` = 'batch-ingestion-patc';

DELETE s FROM `schemaversion` s
  JOIN `schemaversion` f ON f.`versionnumber` = 'portal-mysql57-compat-patch'
  WHERE s.`versionnumber` = 'portal-mysql57-compa';
UPDATE `schemaversion` SET `versionnumber` = 'portal-mysql57-compat-patch'
  WHERE `versionnumber` = 'portal-mysql57-compa';

-- Record patch as applied only after all statements above succeed (see fix 049d77172 for 3.1).
INSERT IGNORE INTO schemaversion (versionnumber) values ("schemaversion-width-patch");
