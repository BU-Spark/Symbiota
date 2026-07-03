
-- DWCA ingestion ingests the data firstly into the uploadspectemp table
-- That uploadspectemp table's eventDate column uses date format, when it should be
-- varchar(32) like the omoccurrences table. Not sure if it's intended, but this fixes it for now:
ALTER TABLE `uploadspectemp` MODIFY `eventDate` varchar(32);

-- MORE NOTES: This patch has not been updated since switching to using the newer Symbiota version, so it
-- needs to be investigated if this bug has been fixed. If so, this patch is not needed anymore.
-- Record patch as applied only after all statements above succeed (see fix 049d77172 for 3.1).
INSERT IGNORE INTO schemaversion (versionnumber) values ("batch-ingestion-patch");
