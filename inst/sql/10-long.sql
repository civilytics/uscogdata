CREATE OR REPLACE VIEW long AS
SELECT *
FROM read_parquet('{url}data/long/**/*.parquet', hive_partitioning = true);
