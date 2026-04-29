CREATE OR REPLACE VIEW gov_population_yearly AS
SELECT DISTINCT
  year,
  canonical_govid,
  population,
  popyear
FROM long
WHERE population IS NOT NULL;
