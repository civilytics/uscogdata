-- Category crosswalk. Numbered 11 (not with the other reference tables at
-- 30+) because the flow views (20-25) classify by MEMBERSHIP in this table
-- and DuckDB binds a view's sources eagerly at CREATE VIEW time, so it must
-- already exist when they register.
CREATE OR REPLACE VIEW summary_categories AS
SELECT *
FROM read_parquet('{url}data/summary_categories.parquet');
