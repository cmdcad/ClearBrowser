# PointsTrack

PointsTrack appears beside ReloCalc, BingBot, and Text Reader in ClearBrowser's Apps hub. Like Text Reader, it currently requires no purchase. Build and run the updated ClearBrowser iOS target to see it; these changes do not update an existing installation automatically.

Create categories such as Hotmail. Each stores its own current point balance, maximum daily earnings (default 280), monthly full-search bonus (default about 1,250), points per reward (default 6,500), and reward value (default USD 5). The monthly bonus applies separately to every category. Edit the current balance manually as you earn or redeem points. Changes persist locally in Application Support/PointsTrack/categories.json; no account sign-in or sync is required.

Current equivalent value = current points / points per reward × reward dollars. Whole-reward redeemable value = floor(current points / points per reward) × reward dollars. Redemption thresholds apply separately to each category; remaining points are not pooled. Dollar totals sum the separately converted category values, using Decimal arithmetic and rounding for display only.

Projections add daily maximum × selected days and one monthly bonus for each completed 30-day period to each category's entered balance. Choose 30 days, 90 days, one year (365 days), or a custom period of 0–36,500 days. The selected period persists. Projections assume unchanged rates, maximum earnings every day, each monthly search bonus is earned, no spending, and no expiry. They do not automatically accrue points into saved balances. USD is the common currency for all category totals.

Example: zero starting points at 280 points/day plus 1,250 points per completed 30-day period produces 117,200 points in 365 days. At 6,500 points = $5, this is approximately $90.15 in equivalent value and $90 in whole rewards.

Input amounts are nonnegative, with a maximum of 1 trillion per field. Conversion amounts must be at least 0.000001. Blank balance, daily earnings, and monthly bonus inputs mean zero; negative and malformed inputs cannot be saved. Numeric zero values appear as placeholders so they can be entered without first deleting a leading zero. Enter decimal numbers using the device's decimal separator, without grouping separators. Older saved categories without a monthly bonus use the 1,250-point default. An unreadable saved file is preserved instead of overwritten.

Xcode build and device verification are required. This Windows workspace has no Swift/iOS toolchain. See tests/PointsTrackTests/README.md.
