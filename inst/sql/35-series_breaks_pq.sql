CREATE OR REPLACE VIEW series_breaks_pq AS
SELECT *
FROM read_parquet('{url}data/series_breaks.parquet');
