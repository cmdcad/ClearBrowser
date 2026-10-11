# BingBot

Native SwiftUI companion to ReloCalc and CreditTrack. Dashboard displays progress; Browser hosts the manual search workflow; Queries manages the library; Settings manages the daily target and backups.

## Run

- iOS: Open ClearBrowser.xcodeproj, build, then open More > Apps > BingBot > Browser.
- macOS 14+: Open BingBotMac.xcodeproj and run BingBot.
- Tests on a Mac: Run `swift test` from the repository root. Use the Xcode app bundle for website sign-in and notification tests.

## Copy and search

1. In the Browser screen, tap Copy Next Query above the web page. The tab bar is navigation-only.
2. Paste into Bing's search box and submit the search yourself.
3. A successfully completed main-frame navigation to a changed Bing `/search?q=...` query updates today's count. Copying, failed loads, refreshes, pagination, Back, and unrelated pages do not count.
4. Each normalized query counts once per local calendar day, including manually typed queries. It does not have to come from the clipboard.
5. The queued item advances only after its matching search completes. Repeated copy taps offer the same uncompleted item. Queue position and daily consumed query keys survive relaunch. Local-date rollover resets daily progress.

No searches are automatically initiated. Dashboard has no search controls. Counts reflect completed search navigation, not confirmed rewards.

## Saved sessions and data

- BingBot uses a dedicated persistent WebKit website store with a stable identifier. Website cookies and storage remain available across reopening and relaunch, separate from ClearBrowser's default browser store.
- Sign in once after updating from the temporary-session version. Microsoft may still expire or revoke sessions.
- No website form or credential inspection, browser data copying, or browser data exports are implemented. WebKit maintains login state.
- Clear Browser Session asks for confirmation and deletes only BingBot website data. Queries, preferences, and daily progress remain.
- Queries are atomically saved to Application Support/BingBot/queries.json. Preferences, daily counts, consumed query keys, and queue position use bingbot.settings.v1 in UserDefaults. Raw paste drafts and browser URLs are excluded from app persistence and exports.
- Backups validate approved fields. Legacy delay settings remain readable for version 1.0 backup compatibility but are unused and hidden. BingBot has no Firebase integration.

## Verification

XCTest covers parsing, backup validation, copying without counting, matching-query consumption, unrelated typed searches, daily deduplication across relaunch, rollover, completed/failed/refresh/history URL observations, query queue changes, failed storage writes, and URL validation.

On a Mac or iPhone:

1. Sign in to Bing, return to Apps, reopen BingBot, and relaunch. Website login should remain unless Microsoft expires it.
2. Copy twice without submitting a search. Count and position stay unchanged. Submit the pasted query and wait for completion: count increases once and the next copy offers the next query.
3. Refresh, paginate, use Back, and repeat a query with a different letter case. No extra daily count should appear. A different successfully completed query should count.
4. Attempt an offline search: no count. Reconnect and submit again.
5. Export/import and verify queries/progress with no website login data in JSON.
6. Clear Browser Session: BingBot signs out, with ClearBrowser's other sessions and query data unchanged.

Swift/Xcode and device testing are unavailable on the Windows host. Builds, XCTest execution, and live WebKit verification require macOS.
