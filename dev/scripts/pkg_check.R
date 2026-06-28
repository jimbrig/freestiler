pkg_path <- this.path::this.proj()
check_root <- file.path(pkg_path, "dev", "check")
check_output_path <- file.path(check_root, "freestiler.Rcheck")

if (!fs::dir_exists(check_root)) {
  fs::dir_create(check_root, recurse = TRUE)
}

if (fs::dir_exists(check_output_path)) {
  fs::dir_delete(check_output_path)
}

attachment::att_amend_desc()

empty_makevars <- tempfile(fileext = ".mk")
file.create(empty_makevars)

withr::with_envvar(
  c(
    R_MAKEVARS_USER = empty_makevars
  ),
  {
    rcmdcheck::rcmdcheck(
      path = pkg_path,
      check_dir = check_root,
      args = c("--no-manual", "--as-cran", "--no-examples", "--no-tests"),
      error_on = "never"
    )
  }
)

file.copy(file.path(check_output_path, "00check.log"), file.path(check_root, "00check.log"), overwrite = TRUE)
file.copy(file.path(check_output_path, "00install.out"), file.path(check_root, "00install.out"), overwrite = TRUE)