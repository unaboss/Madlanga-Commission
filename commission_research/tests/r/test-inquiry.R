test_that("the committed app settings are for the Madlanga Commission", {
  expect_equal(INQUIRY$short_name, "Madlanga Commission")
  expect_true(nzchar(INQUIRY$disclaimer))
  expect_true(is_focus_label("Lt Gen Nhlanhla Mkhwanazi"))
  expect_false(is_focus_label("Lt Gen Khumalo"))
})

test_that("missing settings fall back to neutral defaults, and the disclaimer can't be blanked", {
  dir <- withr::local_tempdir()
  expect_equal(load_inquiry_settings(file.path(dir, "none.json"))$short_name, "Inquiry")

  path <- file.path(dir, "inquiry.json")
  jsonlite::write_json(list(short_name = "Test Inquiry", disclaimer = "",
                            focus_person = list(match = "")), path, auto_unbox = TRUE)
  cfg <- load_inquiry_settings(path)
  expect_equal(cfg$short_name, "Test Inquiry")
  expect_equal(cfg$disclaimer, DEFAULT_DISCLAIMER)
  expect_equal(cfg$branding$product_name, "Commission Research")
  expect_false(any(is_focus_label(c("Anyone", "Mkhwanazi"), match = cfg$focus_person$match)))
})
