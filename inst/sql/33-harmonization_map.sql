CREATE OR REPLACE VIEW harmonization_map AS
SELECT *
FROM read_parquet('{url}data/harmonization_map.parquet');
