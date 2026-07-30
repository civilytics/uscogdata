CREATE OR REPLACE VIEW code_set AS
SELECT *
FROM read_parquet('{url}data/code_set.parquet');
