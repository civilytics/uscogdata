CREATE OR REPLACE VIEW representation AS
SELECT *
FROM read_parquet('{url}data/representation.parquet');
