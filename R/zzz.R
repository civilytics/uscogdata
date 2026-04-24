# R/zzz.R

.onLoad <- function(libname, pkgname) {
  invisible(NULL)
}

# Silence R CMD check "no visible binding" for tidy-eval pronouns used in
# dplyr verbs. `.data` comes from rlang and is guaranteed to resolve at
# evaluation time inside dplyr data-masking contexts.
utils::globalVariables(c(".data"))

.onUnload <- function(libpath) {
  cog_close()
}
