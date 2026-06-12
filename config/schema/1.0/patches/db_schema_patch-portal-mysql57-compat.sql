INSERT IGNORE INTO schemaversion (versionnumber) values ("portal-mysql57-compat-patch");

-- Portal compatibility fixes for MySQL 5.7 / STRICT_TRANS_TABLES SQL_MODE.
--
-- These two changes were previously carried as local edits inside the vendored
-- upstream file config/schema/3.0/patches/db_schema_patch-3.4.sql. That file has
-- been reverted to its upstream (origin/base/3.4.1) state so it stays a clean
-- vendor copy; the portal-specific compatibility tweaks now live here instead.
--
-- Apply this patch AFTER db_schema_patch-3.4.sql (it expects the
-- omoccurdeterminations and mediametadata tables to already exist).
--
-- REQUIRED on MySQL 5.7 (and any server running with STRICT_TRANS_TABLES): under
-- strict mode a `timestamp` column without an explicit NULL/DEFAULT is given an
-- implicit `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`, which
-- breaks the intended "NULL by default" semantics. Making the NULL explicit fixes
-- this. MODIFY COLUMN is naturally idempotent (re-running sets the same definition),
-- so this patch is safe to run more than once.

-- Fix 1: omoccurdeterminations.dateLastModified should be explicitly NULL-able.
ALTER TABLE `omoccurdeterminations`
  MODIFY COLUMN `dateLastModified` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP;

-- Fix 2: mediametadata created_at/updated_at should be explicitly NULL-able.
ALTER TABLE `mediametadata`
  MODIFY COLUMN `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  MODIFY COLUMN `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP;
