CREATE OR REPLACE VIEW revenue_annotated_harmonized AS
SELECT
  s.*,
  x.gov_name       AS xwalk_gov_name,
  x.govs_type,
  x.type_label,
  x.fips_state     AS xwalk_fips_state,
  x.fips_county    AS xwalk_fips_county,
  x.fips_place,
  x.population_acs,
  c.category,
  c.category_type,
  c.revenue_subtype
FROM revenue_long_harmonized s
LEFT JOIN canonical_fips_xwalk x USING (canonical_govid)
LEFT JOIN summary_categories   c USING (item_code);
