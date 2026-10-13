# Recurring bills tests

Add RecurringBillsTests.swift to a ClearBrowser iOS unit-test target in Xcode (the existing Swift package only builds BingBot). Run with a simulator or device. Tests cover all frequency conversions, payoff final payments and insufficient payments, input validation, dashboard integration, JSON round-trip, legacy backup migration, and text/CSV inclusion. These tests have not been executed in the Windows workspace.

Device checks: add/edit/duplicate/delete bills; swipe left and cancel/confirm deletion; category and monthly-amount sorting; optional balance/APR; zero net income burden; relaunch autosave; changing currency; backup import/export; reset bills confirmation. Weekly values are averaged estimates, not a payment calendar. Existing income and destination-cost inputs are retained.
