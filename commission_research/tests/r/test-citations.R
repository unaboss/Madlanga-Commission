test_that("citations use the commission's Day/page/line format", {
  expect_equal(format_citation(47, 23, 10, 23, 15), "Day 47, p.23, lines 10–15")
  expect_equal(format_citation(47, 23, 10, 23, 10), "Day 47, p.23, line 10")
  expect_equal(format_citation(47, 23, 20, 24, 3), "Day 47, p.23 line 20 – p.24 line 3")
})

test_that("older databases without line data still cite day and page", {
  expect_equal(format_citation(47, 23), "Day 47, p.23")
  expect_equal(format_citation(5), "Day 5")
  expect_equal(format_citation(c(0, NA)), c("", ""))
})

test_that("format_citation is vectorised", {
  expect_equal(format_citation(c(1, 2), c(3, 4), c(5, 6), c(3, 4), c(7, 6)),
               c("Day 1, p.3, lines 5–7", "Day 2, p.4, line 6"))
})
