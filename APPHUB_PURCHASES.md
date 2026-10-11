# AppHub purchases

Each AppHub item is a separate non-consumable (one-time) Apple purchase. AppHub opens an app when StoreKit reports a verified current entitlement or an authorized developer override is active. Pending, cancelled and unverified purchases do not unlock access. Transaction updates and foreground refreshes handle purchases and revocations. Restore Purchases calls Apple's sync API. No local preference or Firebase profile field grants access.

| App | Product ID | US price |
| --- | --- | --- |
| ReloCalc | com.mikeso.ClearBrowser.apphub.reloCalc | $2.99 |
| CreditTrack | com.mikeso.ClearBrowser.apphub.creditTrack | $2.99 |
| BingBot | com.mikeso.ClearBrowser.apphub.bingBot | $2.99 |

## Local testing

Add the root AppHub.storekit configuration file to Xcode if needed. In the ClearBrowser scheme, choose Run > Options > StoreKit Configuration > AppHub.storekit. Local transactions are simulated, not real charges. The app displays StoreKit's localized price and disables purchase when a product is unavailable.

Verify each item starts locked, buying one unlocks only that item, relaunch preserves verified access, and Restore Purchases works after reinstall with the same Apple Account. Test cancellation, Ask to Buy/pending approval, failed verification, interrupted purchases and refunds/revocations using Xcode's transaction manager. Check that revocation closes an already open app. Turn off the local configuration before sandbox testing.

## Live sales setup

An enrolled Apple Developer account and App Store Connect setup are required for live sales. Create the three non-consumable products using the exact IDs above, set each US base price to $2.99, supply localization and review information, complete required paid-app agreements, enable the In-App Purchase capability, and submit the products with the app. Local configuration does not set production prices. Other storefronts use Apple's localized prices.

## Scope

This gates the three iOS AppHub entry points. The standalone BingBot Mac app is separate and is not gated by this change. Purchases belong to the Apple Account, not the Firebase account. Server-provided premium content would additionally require server-side transaction verification and authorization; this client gate does not protect public URLs or bundled code against a modified app.

## Developer access

Debug builds expose a Developer access toggle in AppHub. It defaults off on each app launch, unlocks all three items for testing, and does not create or modify purchases. The toggle and its bypass code are excluded from Release builds.

Release builds accept the boolean Firebase Authentication custom claim `developer: true` from the current signed-in account. This is not an editable Firestore profile field. Account access is refreshed on sign-in, sign-out, foregrounding, and via Refresh Account Access in AppHub. A failed claim check removes the override without affecting genuine purchases. Signing out removes developer access.

To activate your account, obtain your UID from Firebase Console > Authentication > Users. On a trusted administrator machine with the firebase-admin Node package installed and Application Default Credentials authorized for your Firebase project, run:

```text
node tools/set-apphub-developer.mjs <firebase-project-id> <your-user-uid> grant
```

Use `revoke` instead of `grant` to remove it. The script preserves other custom claims. Keep administrator credentials outside the app and repository. No Firebase account has been granted access by this code change; the administrator command still needs to run for your account. Afterward sign in and tap Refresh Account Access.

Verify Debug on/off gating, a Release build without the toggle, developer claim true/false/missing, sign-out and switching to a normal account, failed refresh, and claim revocation. Nondeveloper accounts continue to require each separate purchase.
