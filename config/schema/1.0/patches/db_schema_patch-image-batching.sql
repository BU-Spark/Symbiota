INSERT IGNORE INTO schemaversion (versionnumber) values ("image-batching-patch");

-- NOTE: The core `batch` table has been split out into
-- db_schema_patch-batch-core.sql. Apply batch-core FIRST: the tables below
-- (batch_XREF, batch_user) FK to `batch`, so this patch is applied as
-- (batch-core + image-batching). No DROP TABLE here, and every CREATE uses
-- IF NOT EXISTS, so re-running this patch never wipes existing data.

-- Create cross-reference table between the batch table and images table
CREATE TABLE IF NOT EXISTS `batch_XREF` (
  `imgid` int(10) unsigned NOT NULL,
  `batchID` int(11) NOT NULL,
  `ordinal` INT(10) NOT NULL,
  `initialtimestamp` TIMESTAMP NULL DEFAULT current_timestamp,
  PRIMARY KEY (`imgid`,`batchID`),
  KEY `FK_batch_XREF_img` (`imgid`),
  KEY `FK_batch_XREF_batch` (`batchID`),
  CONSTRAINT `FK_batch_XREF_img` FOREIGN KEY (`imgid`) REFERENCES `media` (`mediaID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_batch_XREF_batch` FOREIGN KEY (`batchID`) REFERENCES `batch` (`batchID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Create batch user table
CREATE TABLE IF NOT EXISTS `batch_user` (
  `batch_userID` int(10) NOT NULL AUTO_INCREMENT,
  `batchID` int(10) NOT NULL,
  `uid` int(10) unsigned NOT NULL,
  `last_position` int(10) NOT NULL,
  `initialtimestamp` TIMESTAMP NULL DEFAULT current_timestamp,
  PRIMARY KEY (`batch_userID`),
  KEY `FK_batch_user_batch` (`batchID`),
  KEY `FK_batch_user_user` (`uid`),
  CONSTRAINT `FK_batch_user_batch` FOREIGN KEY (`batchID`) REFERENCES `batch` (`batchID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_batch_user_user` FOREIGN KEY (`uid`) REFERENCES `users` (`uid`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `images_barcode` (
  `imgid` int(10) unsigned NOT NULL,
  `barcode` varchar(255) NOT NULL,
  `occid` int unsigned NOT NULL,
  PRIMARY KEY (`barcode`),
  KEY `FK_images_barcode_images` (`imgid`),
  KEY `FK_images_barcode_omoccurrences` (`occid`),
  CONSTRAINT `FK_images_barcode_images` FOREIGN KEY (`imgid`) REFERENCES `media` (`mediaID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_images_barcode_omoccurrences` FOREIGN KEY (`occid`) REFERENCES `omoccurrences` (`occid`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
