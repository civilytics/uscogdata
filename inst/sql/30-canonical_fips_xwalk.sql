CREATE OR REPLACE VIEW canonical_fips_xwalk AS
SELECT *
FROM read_parquet('{url}data/canonical_fips_xwalk.parquet');
