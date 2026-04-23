test_that(".cfg resolves defaults, options, and env vars in priority order", {
  withr::with_options(list(uscogdata.manifest_ttl_secs = NULL), {
    withr::with_envvar(c(USCOGDATA_MANIFEST_TTL_SECS = NA), {
      expect_equal(uscogdata:::.cfg("manifest_ttl_secs"), 3600L)
    })
  })

  withr::with_options(list(uscogdata.url = "https://opt.example/"), {
    withr::with_envvar(c(USCOGDATA_URL = NA), {
      expect_equal(uscogdata:::.cfg("url"), "https://opt.example/")
    })
  })

  withr::with_envvar(c(USCOGDATA_URL = "https://env.example/"), {
    withr::with_options(list(uscogdata.url = "https://opt.example/"), {
      expect_equal(uscogdata:::.cfg("url"), "https://env.example/")
    })
  })
})

test_that(".resolve_cache_dir falls back to R_user_dir", {
  withr::with_envvar(c(USCOGDATA_CACHE_DIR = NA), {
    withr::with_options(list(uscogdata.cache_dir = NULL), {
      expect_equal(uscogdata:::.resolve_cache_dir(),
                   tools::R_user_dir("uscogdata", "cache"))
    })
  })
})
