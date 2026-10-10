
# CreditTrack — Prompt-Only Build Specification

## ROLE

You are building a single-file HTML/CSS/JS web app called **CreditTrack** — a credit card payment tracker for someone relocating. It is a companion sub-app to ReloCalc and must share the exact same visual design language.

---

## DELIVERY FORMAT

- One self-contained `.html` file
- No external CDNs, no frameworks, no build tools
- Pure HTML + CSS + JavaScript
- If too large for one response, split into 3 files: `styles.css`, `index.html`, `app.js`

---

## DESIGN SYSTEM (Match ReloCalc Exactly)

### Colors:
- Primary blue: `#1A73E8`, light: `#E8F0FE`
- Green (positive/paid): `#34A853`, bg: `#E6F4EA`
- Yellow (warning/due soon): `#F9AB00`, bg: `#FEF7E0`
- Red (overdue/negative): `#EA4335`, bg: `#FCE8E6`
- Page background: `#F0F2F5`, cards: white
- Text: primary `#1A1A2E`, secondary `#5F6368`, tertiary `#9AA0A6`
- Border: `#E0E0E0`

### Typography:
- Currency/numbers: monospace (SF Mono, Consolas)
- Everything else: system-ui sans-serif
- Section headers: tiny uppercase, letter-spaced, gray

### Components:
- Cards: white, 10px radius, subtle shadow, 1px border
- Progress bars: rounded, colored fill on gray track
- Badges: tiny pill-shaped, colored background + text
- Bottom nav: fixed, 4 equal tabs with icons
- Modals: fixed overlay, centered white box, slide-up feel
- Toast: fixed bottom-center, auto-dismiss after 2.5 seconds
- FAB: floating action button, bottom-right, circular, blue with shadow
- Header: linear gradient blue (#1A73E8 → #0D47A1), white text, credit card icon + "CreditTrack" title

---

## NAVIGATION

4 tabs via hidden radio inputs + CSS `:checked` selectors. Bottom tab bar fixed to viewport.

| Tab | Icon | Label | Purpose |
|-----|------|-------|---------|
| 1 | Credit card | Cards | List all creditors, add/edit/delete, mark paid |
| 2 | Pie chart | Summary | Dashboard with totals, progress, payoff timeline |
| 3 | Bell | Reminders | Configure notification schedules |
| 4 | Clock | History | Full payment log grouped by month |

---

## DATA MODEL

### Card:
- `id` — unique identifier
- `name` — creditor name (string, e.g. "Chase Sapphire")
- `initialTotal` — optional starting balance (number or null)
- `fixedPayment` — fixed amount per period (number)
- `dueDate` — next due date (ISO string YYYY-MM-DD)
- `period` — billing cycle: "weekly", "biweekly", "monthly", "quarterly", or "annual"
- `totalPaid` — running sum of all payments made (starts at 0)
- `isActive` — boolean, false when paid off
- `createdAt` — ISO timestamp

### Payment:
- `id` — unique identifier
- `cardId` — reference to card ID
- `amount` — payment amount
- `paidDate` — ISO date when paid
- `periodLabel` — display label (e.g. "October 2026")
- `balanceBefore` — balance before this payment
- `balanceAfter` — balance after this payment

### Reminder:
- `id` — unique identifier
- `daysBefore` — integer (0 = same day, 1 = 1 day before, etc.)
- `timeHour` — 0-23
- `timeMinute` — 0-59
- `appliesToAll` — boolean (true = all cards)
- `specificCardId` — card ID if not all (null otherwise)
- `isEnabled` — boolean toggle

---

## PERSISTENCE

All data stored in **localStorage** under three keys:
- `ct_cards` — JSON array of card objects
- `ct_payments` — JSON array of payment objects
- `ct_reminders` — JSON array of reminder objects

Load on page init. Save after every mutation. App must work fully offline.

---

## TAB 1: CARDS

### Empty State:
When no cards exist, show centered placeholder with credit card icon, "No credit cards yet" heading, and "Tap + to add your first creditor" subtext.

### Card List:
Each active card displayed as a card component showing:
- **Header row**: creditor name (left, bold) + status badge (right, pill-shaped)
- **Info row**: payment amount + period label (left), due date (right, colored by status)
- **Progress bar**: only shown if initialTotal is set. Shows totalPaid / initialTotal with percentage. Color matches status.
- **Action buttons row**: "✅ Mark Paid" (primary blue, full width minus edit/delete), "✏️" edit button, "🗑️" delete button

Cards sorted by due date ascending (most urgent first).

### Card Status Logic:
| Condition | Status | Badge Color | Badge Text |
|-----------|--------|-------------|------------|
| Remaining balance ≤ 0 | Paid Off | Green | "PAID OFF!" |
| Due date < today | Overdue | Red | "OVERDUE Xd" |
| Due date = today | Due Today | Yellow | "DUE TODAY" |
| Due date within 3 days | Due Soon | Yellow | "X DAYS" |
| Due date > 3 days away | On Track | Green | "X DAYS" |

### FAB (Floating Action Button):
Bottom-right "+" button opens the Add Card modal.

### Add/Edit Card Modal:
Slide-up modal with fields:
1. **Creditor Name** — text input, required
2. **Total Amount Owed** — number input with $ prefix, optional
3. **Fixed Payment Amount** — number input with $ prefix, required
4. **Next Due Date** — date picker, defaults to today
5. **Billing Period** — dropdown: Weekly, Bi-weekly, Monthly (default), Quarterly, Annual

Cancel and Save buttons. Validate: name not empty, payment > 0, date set.

In edit mode, pre-fill all fields from existing card data.

### Mark Paid Flow:
1. User taps "Mark Paid" → confirmation modal appears
2. Modal shows: creditor name, payment amount, period label, remaining balance after payment, next due date
3. If this payment will pay off the card (remaining ≤ payment), show green highlight: "🎉 This will pay off the card!"
4. On confirm:
   - `totalPaid` increases by `fixedPayment`
   - A payment record is created with balanceBefore and balanceAfter
   - If remaining balance ≤ 0: set `isActive = false`, show celebration overlay
   - Otherwise: advance `dueDate` by one period
   - Save to localStorage, re-render all tabs, reschedule notifications

### Date Advancement Logic:
| Period | Advance By |
|--------|-----------|
| Weekly | +7 days |
| Bi-weekly | +14 days |
| Monthly | +1 calendar month |
| Quarterly | +3 calendar months |
| Annual | +1 year |

### Delete Card:
Browser confirm dialog → remove from array → save → re-render.

### Paid Off Celebration:
Full-screen overlay with 🎉 emoji (64px), "Card Paid Off!" heading, congratulations message with card name, and "Awesome!" dismiss button. Spring animation on appear.

---

## TAB 2: SUMMARY DASHBOARD

All values computed from current card and payment data. No inputs on this tab.

### Section 1: Total Debt (top card, centered)
- "TOTAL DEBT" section header
- Large monospace number showing total remaining across all cards (red if > 0, green if 0)
- Progress bar: totalPaid / totalInitialDebt
- Caption: "$X paid of $Y (Z%)"

### Section 2: Monthly Snapshot
Key-value rows:
- Total Monthly Payments: sum of all active cards' fixedPayment
- Cards Active: count of active cards
- Cards Paid Off: total cards minus active
- Next Payment Due: earliest due date among active cards, colored by that card's status

### Section 3: Payoff Timeline
For each active card:
- Card name (left) + "X months left" (right, monospace)
- Individual progress bar colored by status
After all cards: "🎯 Debt-free by: [latest estimated payoff date]" in green

Months remaining = ceil(remainingBalance / fixedPayment).
Estimated payoff date = today + months remaining.
Debt-free date = the latest payoff date among all active cards.

### Section 4: This Month
List each active card with:
- ✅ icon if paid this month, ⚠️ if overdue/due today, ⬜ if upcoming
- Card name, payment amount (monospace), due date

### Section 5: Export & Backup
Three export buttons (same style as ReloCalc export buttons):
1. **CSV Export** — green icon, "For Excel, Google Sheets" — downloads full report as .csv
2. **JSON Backup** — yellow icon, "Save & restore later" — downloads all data as .json
3. **Import Backup** — purple icon, "Restore saved JSON" — file picker, parses JSON, restores all data, triggers re-render

---

## TAB 3: REMINDERS

### Notification Permission:
At top of tab, check browser Notification API status:
- **Not supported**: show disabled message
- **Denied**: show "blocked" message with instructions
- **Not yet asked**: show "Enable Notifications" button that calls `Notification.requestPermission()`
- **Granted**: hide this section

### Active Reminders List:
Each reminder shown as a row with:
- Green/gray dot (enabled/disabled)
- Label: "Same day", "1 day before", "3 days before", "1 week before", etc.
- Time: "🕐 9:00 AM"
- Scope: "All cards" or "[Card Name] only"
- Toggle switch (enable/disable)
- Delete (✕) button

### Add Reminder Button:
Opens Add Reminder modal with:

**When?** — Preset pill buttons: Same day, 1 day, 2 days, 3 days, 1 week. One selected at a time (highlight blue).

**Time?** — Time input, defaults to 09:00.

**Apply to?** — Radio options: "All cards" (default) + one option per active card ("[Card Name] only").

Cancel and Save buttons. On save: add to reminders array, save to localStorage, re-render, reschedule notifications.

### Notification Engine:
Since browser Notification API doesn't support future scheduling natively, use a **polling approach**:
- Set an interval that checks every 60 seconds
- On each check: for each enabled reminder × each applicable card, check if today's date matches (dueDate minus daysBefore) AND current hour:minute matches the reminder time
- If match: fire a browser Notification with title "💳 Payment Reminder" and body "[Card Name] payment of $X is due [TODAY / in N days]"
- Track fired notifications in localStorage to prevent duplicates (key = reminder ID + card ID + today's date)

---

## TAB 4: HISTORY

### Filter Bar:
Horizontal scrollable row of filter chips: "All" (default) + one chip per card. Selected chip is blue, others are gray. Clicking a chip filters the payment list.

### Payment List:
Grouped by month (e.g. "OCTOBER 2026"), newest month first.

Each payment entry shows:
- ✅ green checkmark icon
- Card name (bold)
- Amount + date (secondary text)
- "Balance: $X → $Y" (monospace, tertiary text)

### Empty State:
If no payments, show centered placeholder with clock icon, "No payments yet" heading, and "Payments will appear here once you mark a card as paid" subtext.

---

## COMPUTED VALUES REFERENCE

| Value | Formula |
|-------|---------|
| Remaining balance | initialTotal − totalPaid (null if no initialTotal) |
| Progress % | totalPaid / initialTotal (0 if no initialTotal) |
| Days until due | dueDate − today (in days, negative = overdue) |
| Months remaining | ceil(remaining / fixedPayment) |
| Payoff date | today + monthsRemaining months |
| Debt-free date | max(payoffDate) across all active cards |
| Is paid off | remaining ≤ 0 (only if initialTotal is set) |

---

## RENDERING STRATEGY

- One master `renderAll()` function that calls `renderCards()`, `renderSummary()`, `renderReminders()`, `renderHistory()`
- Each render function builds its entire section as an innerHTML string and sets it on the container element
- After setting innerHTML, wire up event listeners for buttons within that section
- Call `renderAll()` after every data mutation (add, edit, delete, pay, import)
- Call `renderAll()` on page load after loading from localStorage

---

## EVENT WIRING PATTERN

Since content is rendered via innerHTML, event listeners must be attached AFTER rendering:
- Use `document.querySelectorAll('.btn-pay')` etc. after setting innerHTML
- Loop through and attach click handlers that reference the card/reminder ID via `data-id` attributes
- Modal open/close: add/remove an `.act` class that sets `display:flex`
- Close modals on: cancel button, overlay click, or action completion

---

## EXPORT FORMATS

### CSV:
Sections: Header (app name, date), Cards table (name, total, payment, period, due, paid, remaining, progress, status), Payment History table (date, creditor, amount, before, after), Summary (total debt, total paid, remaining).

### JSON Backup:
Object with: version "1.0", app "CreditTrack", exported timestamp, cards array, payments array, reminders array. Download as `.json`.

### JSON Import:
File picker accepting `.json`. Parse, validate (must have version + app fields), replace all three arrays, save to localStorage, renderAll, reschedule notifications, show toast.

---

## MOBILE-FIRST CONSTRAINTS

- Max content width: 540px, centered
- All touch targets: minimum 44px
- Bottom nav: 56px height, fixed
- FAB: 52px diameter, positioned above bottom nav
- Modals: max-width 460px, max-height 80vh, scrollable
- Font sizes: body 12-13px, headers 14-16px, large numbers 28-36px
- All inputs: minimum height 40px, clear tap targets

---

## FINAL CHECKLIST

Before delivering, verify:
- [ ] Adding a card persists to localStorage and appears in the list
- [ ] Editing a card updates all fields and re-renders
- [ ] Deleting a card removes it and updates summary
- [ ] Mark Paid decreases balance, advances due date, logs payment
- [ ] Mark Paid on final payment triggers paid-off celebration and deactivates card
- [ ] Summary totals, progress bars, and payoff timeline update after every change
- [ ] History shows all payments grouped by month, filterable by card
- [ ] Reminders can be added, toggled, and deleted
- [ ] Notification permission request works
- [ ] Notification polling fires at correct time/day combinations
- [ ] CSV export contains all current data
- [ ] JSON backup captures all three data arrays
- [ ] JSON import restores everything and triggers full re-render
- [ ] All 4 tabs navigate correctly via bottom nav
- [ ] All modals open, display correctly, and close on cancel/overlay/action
- [ ] Toast appears and auto-dismisses
- [ ] App works fully offline (no network required)
- [ ] App works on mobile viewport (≤ 540px)
- [ ] Data survives page refresh (localStorage persistence)
- [ ] Empty states display correctly when no data exists
