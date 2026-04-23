CREATE OR REPLACE VIEW summary_categories AS
SELECT *
FROM read_parquet('{url}data/summary_categories.parquet');
