CREATE OR REPLACE VIEW long AS
SELECT *
-- {long_files} carries its own quoting: a bracketed list of every partition
-- the manifest enumerates, or a single quoted glob on fallback. Do NOT wrap
-- it in quotes. See .long_files_sql() in R/views.R for why a glob alone
-- cannot work over HTTP.
FROM read_parquet({long_files}, hive_partitioning = true);
