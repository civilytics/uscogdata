# R/cache.R
# Local partition cache; SHA-based invalidation.
# Phase N v0.1 implementation: DuckDB httpfs handles actual reads directly
# from Nextcloud; cache_dir holds only manifest.json. Richer partition
# caching (pre-fetch hot partitions) is a v0.2 feature.
# Stub here for cog_mirror to compose against.
