# R/zzz.R

.onLoad <- function(libname, pkgname) {
  invisible(NULL)
}

.onUnload <- function(libpath) {
  cog_close()
}
