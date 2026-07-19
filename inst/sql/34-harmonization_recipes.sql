CREATE OR REPLACE VIEW harmonization_recipes AS
SELECT *
FROM read_parquet('{url}data/harmonization_recipes.parquet');
