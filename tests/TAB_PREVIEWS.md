# Tab preview device verification

Snapshots use WKWebView.takeSnapshot (available since iOS 11 / macOS 10.13). ClearBrowser's TabManagerView and BrowserView are UIKit based; this change targets the existing iOS app and does not port its tab manager to macOS.

On iOS 17 or newer:
1. Open two pages. Open Tabs after each loads. Verify each card shows the correct page, title and host.
2. Scroll a page, open Tabs, and verify its preview refreshes to the visible portion.
3. Close and relaunch the app. Saved normal previews should appear before reloading their pages.
4. Navigate to a different URL or rapidly switch tabs while a snapshot is pending. A preview must never attach to a different page or re-create a closed tab's file.
5. Close a tab. Its image should disappear and its TabPreviews/<UUID>.json file should be deleted.
6. Enable private mode and load a distinctive page. Its preview should show during the session without being written to disk. Disable private mode; private previews must clear. Restart and verify that no private screenshot returns.
7. Simulate snapshot failure or unwritable storage. Tab URLs and titles remain usable; a globe placeholder appears without a preview.

Images are compressed JPEGs inside URL-tagged JSON records, atomically written to Application Support with complete file protection. They are local last-viewed images, not live pages or offline browsing. They are not synced to Firebase. Uninstalling removes them unless restored by a device backup. Orphaned files are cleaned on launch.

Xcode/device checks remain required; this Windows workspace cannot run WebKit or build the iOS target.
