# BingBot

Native SwiftUI companion to ReloCalc and CreditTrack. The four destinations are Dashboard, Browser, Queries, and Settings. The embedded browser uses a fresh, nonpersistent WebKit data store; it does not share ClearBrowser's browser, Firebase account, or browser session.

## Run

- **iOS 17.5+:** Open `ClearBrowser.xcodeproj`, build ClearBrowser, then open **More → Apps → BingBot**.
- **macOS 14+:** Open `BingBotMac.xcodeproj`, select BingBot, and run. This is a standalone app bundle using the same source files with sidebar navigation. Select your signing team if Xcode requests one.
- **Unit tests on a Mac:** From the repository root, run `swift test`. `Package.swift` exposes the same sources and XCTest suite without external packages. Use the Xcode app bundle to run BingBot, especially to test notification permission and delivery.

## Data and behavior

- Queries are written atomically to `Application Support/BingBot/queries.json`.
- Only BingBot's `bingbot.settings.v1` preferences, local-date progress, used query strings, frozen query queue, and position are stored in UserDefaults.
- Pasted drafts, current browser address, navigation URLs, browser history, cookies, and browser sessions are excluded from persistent data and exports. No Firebase or account integration is used in BingBot.
- Query changes affect the next prepared queue. Pause/Stop preserve position; relaunch restores the queue paused. A search interrupted before successful navigation is retried rather than counted.
- Automated searches count once after the associated WebKit navigation finishes at the expected Bing search URL. Failed HTTP responses, refreshes, unrelated browsing, and stale callbacks do not count. This is app progress, not confirmation of external rewards.
- iOS pauses automation when the app leaves the foreground. Mac close-on-completion is optional, displays a five-second countdown, and can be canceled.
- Imports validate the version, data types, bounds, and allowed fields before changing data. Merge is the default; replacing the library requires confirmation. Browser/account fields are rejected. JSON backups include approved preferences and daily progress.

## Verification

The XCTest suite covers Unicode and case normalization, words/phrases/sentences, quotation errors, imported privacy fields and settings ranges, duplicate edits, frozen queues, stale callbacks, failed navigations, completion versus exhaustion, partial-progress restoration, daily rollover, URL scheme restrictions, and preservation of pasted input after a failed storage write.

On a Mac/iPhone, also verify:

1. Paste the specification examples in all three parsing modes, check preview counts, add, edit, and relaunch.
2. Set a target of two. Test Manual and Auto; interrupt a search with Pause/Stop, disconnect networking, and retry. Progress should count only successful matching navigations.
3. Browse manually while automation is running. Automation should pause and the manual page should not count.
4. Clear the browser session, then relaunch. Website session state should be gone; queries and progress should remain.
5. Export/import using Merge and Replace. Try a backup with an `accounts` field; it must be rejected without changing existing data.
6. Background the iOS app during a run, then return and explicitly resume. On macOS, test canceling the close countdown.
7. Enable completion notifications and check delivery in the built app bundle. Permission denial must leave query editing and searches usable.

Swift, Xcode, and Apple device testing are unavailable on the Windows implementation host; the XCTest suite and Apple builds need to be run on macOS.
