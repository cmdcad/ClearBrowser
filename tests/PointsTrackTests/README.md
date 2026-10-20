# PointsTrack tests

Add PointsTrackTests.swift to a ClearBrowser iOS unit-test target in Xcode. The root Swift package builds BingBot only. These tests have not run in this Windows workspace, which has no Swift compiler or Xcode.

Coverage: default one-year projection, existing balances, independent conversion rates, per-category reward thresholds, zero earnings, input validation, locale decimal parsing, save/edit/delete/reload, and preservation of unreadable saved data.

Device checks: open PointsTrack from Apps without waiting for StoreKit; add Hotmail at the defaults; edit its balance; add another category with a different conversion; try 30/90/365/custom days; confirm forecasts leave balances unchanged; cancel editing/deletion; relaunch to check persistence; test invalid and zero inputs, large Dynamic Type, and light/dark appearance.
