# uscogdata

Curated R reader for the Civilytics US Census of Governments finance corpus.

Provides unit-level financial profiles, geographic rollups, and peer comparisons
with auditable provenance and built-in cross-vintage correctness. Reads the
published corpus (Hive-partitioned parquet + manifest.json) directly from
Nextcloud via DuckDB httpfs — no local bulk downloads required.

## Status

Under active development (Phase 2 of the cog_pipeline project). See
`../cog_pipeline/docs/reader-specification.md` for the reader contract this
package implements.

## Installation

```r
# pak::pkg_install("gitea.civilytics.org/Civilytics/uscogdata")
```

## Configuration

- `USCOGDATA_URL` — corpus root URL (public Nextcloud share, trailing slash)
- `USCOGDATA_CACHE_DIR` — optional override for the manifest cache directory
- `USCOGDATA_MANIFEST_TTL_SECS` — optional manifest re-fetch TTL (default 3600)
