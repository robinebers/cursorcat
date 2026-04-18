# Cursorcat — macOS Menu Bar Tray for Cursor Spend

## Context

A minimal, always-on macOS menu bar companion that shows today's Cursor spend live in the tray next to a small animated pixel cat. Clicking opens a native menu with yesterday / last 7 days / billing cycle / plan-limit details. Built in Swift for minimal memory footprint.

Replaces the habit of checking `cursor.com/dashboard`. Keeps spend top-of-mind without interrupting flow.

Two reference tools live on disk and inform the data/auth layer:
- `/Users/rebers/Dev/cstats` — TypeScript CLI that hits the Cursor CSV export for per-event data. Source of the auth flow and CSV endpoint.
- `/Users/rebers/Dev/openusage` — Tauri tray app whose Cursor plugin hits Connect RPC for billing-cycle totals, plan, quotas. Source of the RPC endpoint shapes and account-type detection heuristic.

Cursorcat unifies both approaches: one CSV call for today/yesterday/7-day granularity, one RPC call cluster for billing-cycle total, plan, quotas, credits.

## Target & toolchain

- **Xcode project** (not SPM) — signing, Info.plist, asset catalog
- **macOS 15+ (Sequoia) minimum**, no ceiling; any Tahoe-specific SwiftUI affordance is welcome but none required
- Swift 5.x, SwiftUI `@main` shell, AppKit `NSStatusItem` for the tray (MenuBarExtra rejected — limited animated-image support)
- `LSUIElement=1` (agent app, no dock icon, no window)
- **Unsandboxed** — must read `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. Hardened runtime, notarized, no App Store.

## Architecture

Single process, three concurrent subsystems:
- **PollScheduler** — `DispatchSourceTimer` firing every 5 min (+ manual "Refresh now", + wake-from-sleep coalesced poll). Each tick: resolve auth → refresh token if needed → run API fan-out → update `UsageStore`.
- **CatAnimator** — independent Timer at ~3fps driving the tray icon frame index. State machine: `.idle / .blink / .sleep / .error`.
- **StatusItemController** — owns `NSStatusItem`, observes `UsageStore` and `CatAnimator` state, updates `button.title` and `button.image`, rebuilds `NSMenu` on state change.

## Project layout

```
/Users/rebers/Dev/cursorcat/
├── Cursorcat.xcodeproj/
├── Cursorcat/
│   ├── CursorcatApp.swift             // @main SwiftUI shell (WindowGroup → EmptyView), owns AppDelegate
│   ├── AppDelegate.swift              // Wires NSStatusItem, starts scheduler + animator
│   ├── Auth/
│   │   ├── CursorAuth.swift           // Orchestrator: loadAuth → refreshIfNeeded → access token
│   │   ├── CursorSQLite.swift         // Direct SQLite3 C API via `import SQLite3` (no shell-out)
│   │   ├── CursorKeychain.swift       // Security.framework generic-password read/write
│   │   └── JWT.swift                  // base64url decode + JSONDecoder → { sub, exp }
│   ├── API/
│   │   ├── CursorAPI.swift            // Fan-out orchestrator, retry-once-on-401
│   │   ├── DashboardRPC.swift         // Connect RPC POSTs (Bearer auth)
│   │   ├── UsageCSV.swift             // CSV GET + parse (Cookie auth)
│   │   ├── StripeAPI.swift            // /api/auth/stripe (optional, for customer balance)
│   │   └── Models.swift               // Codable structs mirroring RPC/CSV shapes
│   ├── State/
│   │   ├── UsageStore.swift           // Derived today/yesterday/7d/cycle; @Published snapshot
│   │   └── PollScheduler.swift        // 5-min timer + manual + wake triggers
│   ├── UI/
│   │   ├── StatusItemController.swift // NSStatusItem title/image updates, menu rebuilds
│   │   ├── CatRenderer.swift          // CGContext-based pixel frames → NSImage
│   │   ├── CatAnimator.swift          // Frame index Timer + state machine
│   │   └── MenuBuilder.swift          // Builds NSMenu from UsageStore snapshot
│   ├── Assets.xcassets/
│   └── Info.plist                     // LSUIElement=1, bundle id com.sunstory.cursorcat
└── CREDITS.md                         // menubar_runcat + Neko attributions
```

## Auth module

Port of logic from:
- `/Users/rebers/Dev/cstats/src/cursor-auth.ts` (refresh flow, JWT decode, session-token construction)
- `/Users/rebers/Dev/openusage/plugins/cursor/plugin.js:82-128` (two-source preference heuristic)
- `/Users/rebers/Dev/openusage/plugins/cursor/plugin.js:161-227` (refresh + persist-back)

**Token sources, priority order:**
1. SQLite at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
   - Keys in `ItemTable`: `cursorAuth/accessToken`, `cursorAuth/refreshToken`, `cursorAuth/stripeMembershipType`
2. Keychain (macOS `Security.framework`)
   - Services: `cursor-access-token`, `cursor-refresh-token`

**Two-source heuristic** (mirrors openusage): when both present AND SQLite `stripeMembershipType=="free"` AND the two access tokens have different JWT subjects, prefer keychain (user has multiple accounts; paid one typically in keychain).

**SQLite access:** `import SQLite3`. `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE`. Prepared statement with `sqlite3_bind_text` (never manual escaping). `SELECT value FROM ItemTable WHERE key = ? LIMIT 1` and equivalent UPDATE for persist-back.

**Keychain access:** `SecItemCopyMatching` with `kSecClassGenericPassword` + `kSecAttrService`. Write with `SecItemAdd` / `SecItemUpdate`. No iCloud sync.

**JWT decode:** no library. Split on `.`, base64url-decode payload (swap `-`→`+`, `_`→`/`, pad with `=`), `JSONDecoder`:
```swift
struct JWTPayload: Decodable { let sub: String; let exp: Int }
```

**Refresh:** `POST https://api2.cursor.sh/oauth/token`, JSON body:
```json
{ "grant_type": "refresh_token",
  "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
  "refresh_token": "<token>" }
```
Triggered when `exp - now < 5 min`. On success, persist new `access_token` back to the source it came from (sqlite OR keychain). On response with `shouldLogout: true` or HTTP 400/401 → flip to logged-out state.

**Session cookie construction** (for CSV + Stripe endpoints):
```
WorkosCursorSessionToken = <userId>%3A%3A<accessToken>
```
where `userId` = JWT `sub` with provider prefix stripped (e.g., `google-oauth2|user_abc` → `user_abc`).

## API module

### RPC (Bearer auth)
Base: `https://api2.cursor.sh`, Connect RPC v1. Headers on every call:
```
Authorization: Bearer <access_token>
Content-Type: application/json
Connect-Protocol-Version: 1
```
Body: `{}`

Endpoints (all POST):
- `/aiserver.v1.DashboardService/GetCurrentPeriodUsage` — returns `billingCycleStart` / `billingCycleEnd` (Unix ms strings), `planUsage.{totalSpend, limit, autoPercentUsed, apiPercentUsed}` (cents + %), `spendLimitUsage.{individualLimit, individualRemaining, pooledLimit, pooledRemaining, limitType}`
- `/aiserver.v1.DashboardService/GetPlanInfo` — returns `planInfo.planName` ∈ {Free, Pro, Ultra, Team, Enterprise}
- `/aiserver.v1.DashboardService/GetCreditGrantsBalance` — returns `{hasCreditGrants, totalCents, usedCents}`

Reference: `/Users/rebers/Dev/openusage/plugins/cursor/plugin.js:410-451` and `/Users/rebers/Dev/openusage/docs/providers/cursor.md`.

### REST (Cookie auth)
- `GET https://cursor.com/api/dashboard/export-usage-events-csv?startDate=<ms>&endDate=<ms>&strategy=tokens`
  - Headers: `Cookie: WorkosCursorSessionToken=...`, `Accept: text/csv`
  - CSV columns: `Date, Kind, Model, Max Mode, Input (w/ Cache Write), Input (w/o Cache Write), Cache Read, Output Tokens, Total Tokens, Cost`
- `GET https://cursor.com/api/auth/stripe` (optional) → `customerBalance` (cents, negative = prepaid credit)

Reference: `/Users/rebers/Dev/cstats/src/cursor-export.ts`.

### Fan-out per poll
Four concurrent calls via `async let`:
```swift
async let usage = rpc.getCurrentPeriodUsage()
async let plan  = rpc.getPlanInfo()
async let credits = rpc.getCreditGrantsBalance()
async let csv   = csvClient.fetch(trailingDays: 7)
```
Window for CSV is always trailing 7 days from start-of-today 00:00:00 local → end-of-today 23:59:59 local. This covers today/yesterday/7d with one download; billing-cycle total comes from `usage.planUsage.totalSpend` (no CSV slicing needed).

### Retry
Each request wrapped in retry-once-on-401: on 401, invalidate cached token, call `CursorAuth.refresh()`, retry once. Second 401 → logged-out state.

### Parsing
- **CSV:** roll a minimal `CSVParser` supporting quoted fields with embedded commas. Strip thousands separators (`"1,234"` → `1234`). Parse `Cost` as `Double`. Parse `Date` as ISO8601 → `Date`.
- **Cost:** trust the `Cost` column as-is — **do not** port cstats' pricing manifest (maintenance burden; Cursor's number is what the user is actually billed).
- **Money:** store all money as cents (`Int`) internally; format at render time with `NumberFormatter.currency(.usd)`. Avoids Double drift.

## UsageStore

Single `@MainActor` observable. Fields:
```swift
struct Snapshot {
    var yesterdaySpend: Int?        // cents
    var last7DaysSpend: Int?        // cents
    var billingCycleSpend: Int?     // cents
    var billingCycleResetInDays: Int?
    var plan: String?
    var requestsUsed: Int?
    var requestsLimit: Int?
    var autoPercentLeft: Double?
    var apiPercentLeft: Double?
    var onDemandRemaining: Int?     // cents
    var onDemandLimit: Int?         // cents
    var creditsLeft: Int?           // cents
    var todaySpend: Int?            // cents — drives tray title
    var lastUpdated: Date?
    var lastError: String?
    var isLoggedIn: Bool
}
```

Derivations from CSV (trailing 7d rows, local timezone):
- `todaySpend` = sum of `Cost` where `Date >= startOfToday`
- `yesterdaySpend` = sum where `startOfYesterday <= Date < startOfToday`
- `last7DaysSpend` = sum where `Date >= startOfToday - 7 days`

Derivations from RPC:
- `billingCycleSpend` = `planUsage.totalSpend`
- `billingCycleResetInDays` = `floor((billingCycleEnd - now) / 86400)`
- `autoPercentLeft` = `100 - planUsage.autoPercentUsed`
- `apiPercentLeft` = `100 - planUsage.apiPercentUsed`
- `onDemandRemaining/Limit` = `spendLimitUsage.individualRemaining/individualLimit` (or pooled for team)
- `creditsLeft` = `totalCents - usedCents` (+ `customerBalance` if present and negative)

## Billing cycle

Fully from `GetCurrentPeriodUsage`. No inference needed. `billingCycleStart` / `billingCycleEnd` come as Unix ms strings; parse to `Date` via `Double(str).map { Date(timeIntervalSince1970: $0 / 1000) }`.

## Cat animation

**Style:** Neko-inspired pixel art. 16×16 logical grid, rendered at 2× (32×32 px) into an `NSImage`, attached as `NSStatusItem.button.image` sized to `NSSize(width: 22, height: 22)` points. `isTemplate = false` to keep coloring.

**Frame generation:** procedural in `CatRenderer.swift` using `CGContext`. Each pixel = 1×1 rect at 2x scale. A frame is a compile-time `[[UInt8]]` (16 rows × 16 cols) where each byte indexes into a 4-entry palette (transparent, outline, fill, accent). Helper: `func render(_ frame: [[UInt8]], palette: [CGColor]) -> NSImage`.

**States (v1):**
- `.idle` — 4 frames, slow breathing (head 1px up/down), ~3fps (330ms per frame)
- `.blink` — single frame (eyes closed on idle pose 0), shown for one tick every 4–8s pseudo-random
- `.sleep` — static "Zzz" frame, animator paused (logged-out state)
- `.error` — grumpy static frame

**Reference, not copy:** `menubar_runcat` (Apache-2.0) for the animation-loop pattern; Neko/oneko for sprite proportions. All pixel data authored fresh inline in source. Credit in `CREDITS.md`.

Expandable later: `.eating` on new spend detected, `.shocked` on threshold cross, `.dancing` if the user ever stops spending for a whole day.

## Tray string

- **Logged in:** `button.image = <cat frame>`, `button.title = " $12.34"` (leading space = icon padding). Formatted via `NumberFormatter(numberStyle: .currency, currencyCode: "USD")`.
- **Logged out:** `button.title = " Not logged in"`, sleep cat.
- **Loading (first launch, no snapshot):** `button.title = " …"`, idle cat.
- **Error (no cached snapshot):** `button.title = " ⚠"`, error cat.

## Menu

Rebuilt from `UsageStore.Snapshot` on every update. Rows where data is absent are omitted (no `"—"` placeholders).

**Logged in:**
```
Yesterday: $X.XX                       (disabled)
Last 7 days: $X.XX                     (disabled)
This billing cycle: $X.XX              (disabled)
─────
Plan: Ultra                            (disabled)
Requests: 345/500 left                 (disabled, omit if no cap)
Auto: NN% left                         (disabled)
API: NN% left                          (disabled)
On-demand: $X.XX/$Y.YY left            (disabled, omit if no cap)
Credits: $X.XX left                    (disabled, omit if zero)
Refresh now                            (enabled, ⌘R)
─────
Quit app                               (enabled, ⌘Q)
```

**Logged out:**
```
Open Cursor to log in                  (enabled)
Refresh now                            (enabled, ⌘R)
─────
Quit app                               (enabled, ⌘Q)
```

"Open Cursor to log in" calls `NSWorkspace.shared.open(URL(string: "cursor://")!)` and falls back to opening `/Applications/Cursor.app` if the URL scheme is unregistered. If neither works → no-op, no alert dialog.

## Polling

- **Timer:** `DispatchSourceTimer`, interval 300s, leeway 10s (battery-friendly)
- **Manual:** "Refresh now" → `scheduler.triggerNow()`
- **First launch:** immediate poll
- **Wake from sleep:** `NSWorkspace.didWakeNotification` → one coalesced poll after 3s debounce
- **In-flight:** single concurrent poll, overlapping requests ignored
- **Backoff:** 3 consecutive failures → extend next interval to 15 min until next success

## Error states

| Condition | Result |
|---|---|
| No tokens in SQLite or keychain | Logged-out state |
| Token refresh returns `shouldLogout` | Logged-out state |
| HTTP 401/403 after one refresh retry | Logged-out state |
| Network error, 5xx, timeout | Keep last snapshot, set `lastError`, menu shows italic footer "Last update failed HH:MM" |
| Parse error | Keep last snapshot, log to stderr + log file, set `lastError` |

## Attribution

`CREDITS.md` (new file, root of repo):
- [Kyome22/menubar_runcat](https://github.com/Kyome22/menubar_runcat) (Apache-2.0) — animation-loop pattern reference, no code or assets reused
- Neko (1989, Masayuki Koba; public reference) — visual style inspiration
- OpenUsage Cursor plugin (internal) — RPC endpoint shapes and two-source auth heuristic
- cstats (internal) — auth flow and CSV endpoint shape

## Implementation phases

Each phase independently runnable and verifiable:

1. **Scaffold Xcode project.** Agent app, `LSUIElement=1`, `NSStatusItem` showing static "🐱 $0.00".
2. **Auth module.** SQLite read, keychain read, JWT decode, refresh. Debug menu item "Print auth state" → stderr.
3. **API module.** RPC + CSV + retry. Debug menu item "Fetch once" → stderr dump.
4. **UsageStore + PollScheduler.** Wire API to store, 5-min timer, compute today/yesterday/7d.
5. **MenuBuilder.** Render full logged-in menu from store snapshot.
6. **CatRenderer + CatAnimator.** Procedural pixel cat, idle + blink + sleep states.
7. **Logged-out path.** Auth-absent flip, menu swap, "Open Cursor" action.
8. **Polish.** NumberFormatter currency, error footer, wake-from-sleep, backoff, log file at `~/Library/Logs/Cursorcat/cursorcat.log`.
9. **Packaging.** Info.plist, bundle id `com.sunstory.cursorcat`, icon, CREDITS.md, code signing.

## Verification

### End-to-end manual checks
- **Happy path:** fresh launch on a machine signed into Cursor → tray shows `🐱 $X.YY` within 5s; menu populated; "Refresh now" updates immediately.
- **Logged out:** delete `cursorAuth/accessToken` from SQLite (`sqlite3 state.vscdb "DELETE FROM ItemTable WHERE key LIKE 'cursorAuth/%'"`) → tray flips to "Not logged in"; menu collapses to 3 items.
- **Log-in action:** click "Open Cursor to log in" → Cursor app launches.
- **Network failure:** toggle wifi off → next poll fails silently; snapshot preserved; menu shows "Last update failed HH:MM" footer.
- **Wake from sleep:** close laptop lid for 5+ min, reopen → one poll fires within ~3s.
- **Memory:** `ps -o rss= -p $(pgrep Cursorcat)` stays under 30 MB idle, no growth over 24h.
- **CPU:** Activity Monitor shows <0.1% CPU idle, brief spike during polls.

### Dev loop
- Xcode run scheme with console logging for auth/API trace lines.
- Debug menu item "Copy last API response" copies the most recent raw RPC + CSV responses to clipboard for inspection without breakpoints.
- Log file at `~/Library/Logs/Cursorcat/cursorcat.log` (rotated daily, 3-day retention) — always on.

### Unit-testable pieces
- JWT decode (sample tokens)
- CSV parser (quoted fields with embedded commas and thousands separators)
- Date-window math (today/yesterday/7d boundaries around DST + end-of-month)
- Money formatting (cents → display string, negative handling)
