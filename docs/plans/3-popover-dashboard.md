# Popover dashboard

## Overview

Replace the data-carrying `NSMenu` with a SwiftUI popover anchored to the
menu-bar button. Progress, money, plan, quotas, and errors render as a
proper little dashboard instead of stacked disabled menu items.

The cat icon and its animation stay exactly where they are (in
`NSStatusItem`). Only the click behavior and the chrome that shows usage
data change.

## Interaction model

- **Left-click** on the status button → toggle the popover.
- **Right-click** (or ⌃-click) → a tiny `NSMenu` with just actions:
  Interact ▸ / Refresh now ⌘R / Quit ⌘Q.
- **Outside click** or pressing Escape → popover dismisses
  (`NSPopover.behavior = .transient`).

Status-item title (` $4.82`, ` Not logged in`, ` …`, ` ⚠`) and the
animated cat frames are unchanged.

## Architecture

```mermaid
flowchart LR
  Store[UsageStore<br/>@Published snapshot] --> Dash[DashboardView<br/>SwiftUI]
  Dash --> Host[NSHostingController]
  Host --> Pop[NSPopover]
  Button[NSStatusItem.button] -- leftMouseUp --> Controller
  Button -- rightMouseUp --> Controller
  Controller -- toggle --> Pop
  Controller -- popUp --> Menu[NSMenu<br/>actions only]
```

`StatusItemController` gains two responsibilities: showing/hiding the
popover, and popping up the short action menu on right-click.
`MenuBuilder` shrinks to an actions-only menu. `DashboardView` is new and
owns its data via `@ObservedObject` on `UsageStore`.

## Design language

macOS Tahoe / Liquid Glass, with an explicit "no color coding" rule.

- **No accent tint on data.** Progress bars, numbers, labels are all
  monochrome. Color carries no semantic meaning — values speak for
  themselves. Accent color is reserved for the single primary action
  (Interact) and the focus ring.
- **Materials.** Let `NSPopover` provide its own background. Do not add
  custom opaque fills behind rows. No `.background(.regularMaterial)`
  inside the popover root — it fights the system material.
- **Typography**
  - Row labels (left column): system sans, `.body` weight regular,
    `.foregroundStyle(.primary)`.
  - Row values (right column): `.system(.body, design: .monospaced)` —
    SF Mono, so all values align crisply column-to-column and digits have
    consistent width.
  - Large headline ("Today" value): `.system(size: 28, weight: .semibold,
    design: .monospaced)`.
  - Section labels ("SPEND", "QUOTAS"): `.caption2`, `.textCase(.uppercase)`,
    `.tracking(0.6)`, `.foregroundStyle(.secondary)`.
- **Progress bars.** Custom, monochrome, 4pt tall, capsule shape:
  - Track: `Capsule().fill(.tertiary)` (or `Color.primary.opacity(0.12)`).
  - Fill: `Capsule().fill(.primary.opacity(0.75))` clipped to the value
    fraction.
  - No gradient, no tint, no "low/med/high" color shift.
- **Controls.** Standard SwiftUI — `Button` for the header refresh and
  footer actions. The Interact button uses
  `.buttonStyle(.glass)` (Tahoe glass button). The ellipsis overflow uses
  `.buttonStyle(.glass)` with a capsule shape. No hand-rolled glass.
- **Corners.** Let the system round the popover corners. Internal
  dividers are `Divider()`; no heavy separators.
- **Density.** `.controlSize(.small)` on the footer control group to keep
  the popover compact without dropping below tap targets.

## Layout

Fixed width, vertical stack, ~320pt wide, total ~340–380pt tall
depending on which optional rows are present. Insets: 16pt
horizontal, 14pt vertical.

```
┌───────────────────────────────────────────────┐
│  TODAY                                    ⟳   │  ← header row
│  $4.82                                         │
│                                                │
│  ───────────────────────────────────────────  │
│  SPEND                                         │  ← section label
│  Yesterday                           $6.14    │
│  Last 7 days                        $38.92    │
│  This billing cycle                $104.20    │
│                                    resets 12d │  ← muted subtitle
│                                                │
│  ───────────────────────────────────────────  │
│  QUOTAS                                        │
│  Auto       ████████████░░░░░       72% left  │
│  API        █████░░░░░░░░░░░        34% left  │
│  Requests   █████████░░░░░░░       312/500    │
│  On-demand  ███░░░░░░░░░░░░░        $4/$20    │
│                                                │
│  ───────────────────────────────────────────  │
│  [ Plan: Pro ]              [ 🐾 Interact ][⋯] │  ← footer
└───────────────────────────────────────────────┘
```

Footer:
- Left: muted pill badge with current plan name. Not interactive.
- Right: `Interact` button (glass style) opens a `Menu` of animations
  (Scratch / Sleep / Alert / Run around).
- Far right: `⋯` `Menu` button containing `Refresh now ⌘R`, `About`,
  `Quit Cursorcat ⌘Q`.

## Row composition

A single reusable row view keeps vertical rhythm consistent.

```swift
struct StatRow: View {
    let label: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

And a bar row for quotas:

```swift
struct QuotaRow: View {
    let label: String
    let fraction: Double  // 0...1, what's LEFT
    let value: String     // "72% left", "312/500 left", "$4/$20 left"

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 88, alignment: .leading)
            MonoBar(fraction: fraction)
                .frame(height: 4)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
    }
}

struct MonoBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                Capsule()
                    .fill(.primary.opacity(0.75))
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
    }
}
```

Label column uses a fixed width so all bars start at the same x. Same
trick for the value column so all bars end at the same x.

## States

`DashboardView` branches on snapshot shape:

1. **Loading** (`snapshot.lastUpdated == nil` && logged in):
   Header shows "Today" label and an indeterminate `ProgressView()`
   where the number would be. No sections rendered.
2. **Logged in, data present:** full dashboard as above.
3. **Logged out** (`snapshot.isLoggedIn == false`):
   Single centered card with cat icon (small static idle frame),
   "Not logged in", and a `Button("Open Cursor to log in")` using
   `.buttonStyle(.borderedProminent)` — the one place accent color is
   allowed.
4. **Error banner** (`snapshot.lastError != nil`):
   Compact row at the top of the popover, between header and Spend,
   rendered as `Label(error, systemImage: "exclamationmark.triangle")`
   in `.secondary` foreground with a thin rounded-rect background. No
   red tint — the icon carries the semantic.

Rows with missing data (`yesterdaySpend == nil`, etc.) are omitted
individually, matching current `MenuBuilder` behavior. Whole sections
collapse if none of their rows are present.

## Popover lifecycle

File: [Sources/Cursorcat/UI/StatusItemController.swift](../../Sources/Cursorcat/UI/StatusItemController.swift)

- Build once in `init`:
  ```swift
  popover = NSPopover()
  popover.behavior = .transient
  popover.animates = true
  popover.contentViewController = NSHostingController(
      rootView: DashboardView(store: store, actions: actions)
  )
  ```
- Replace the current `statusItem.menu = menuBuilder.build(...)` line.
  Instead, wire a click handler:
  ```swift
  button.action = #selector(handleStatusButton(_:))
  button.target = self
  button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  ```
- `handleStatusButton` branches on `NSApp.currentEvent?.type`:
  - `.rightMouseUp` → `statusItem.menu = actionsMenu; button.performClick(nil); statusItem.menu = nil` (the idiom for transient right-click menus without blocking left-click action).
  - else → toggle popover:
    ```swift
    if popover.isShown {
        popover.performClose(nil)
    } else {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    ```
- `NSApp.activate(ignoringOtherApps: true)` on show so focus moves to
  the popover (agent app needs the nudge).
- Keep `animator.onFrame` wiring unchanged.

## Actions wiring

An `Actions` struct is passed into `DashboardView` so the view stays
pure and doesn't import AppKit specifics:

```swift
struct DashboardActions {
    let refresh: () -> Void
    let openCursor: () -> Void
    let interact: (CatAnimation) -> Void
    let quit: () -> Void
}
```

`StatusItemController` constructs this from its existing `@objc`
methods. Same functions back both the popover buttons and the
right-click `NSMenu`, so there is exactly one implementation of each
action.

## MenuBuilder changes

File: [Sources/Cursorcat/UI/MenuBuilder.swift](../../Sources/Cursorcat/UI/MenuBuilder.swift)

- Delete everything that renders data rows (Yesterday, Last 7 days,
  billing cycle, Plan, Requests, Auto, API, On-demand, Credits, error
  row).
- Rename to reflect its new role: `ActionsMenuBuilder`. Keep the
  `interactions` array and `animation(forTag:)` helpers — they are
  reused both by the popover's Interact menu and the right-click
  `NSMenu`.
- `build()` now returns:
  - `Interact ▸` (submenu with 4 items)
  - `Refresh now ⌘R`
  - separator
  - `Quit Cursorcat ⌘Q`
- Logged-out variant only swaps in `Open Cursor to log in` above the
  Interact entry.

The `Money` enum and `NSFont.italics()` helper both move into
`Support/` as `Money.swift` since the popover also needs currency
formatting. `italics()` deletes — no longer used.

## New files

- `Sources/Cursorcat/UI/DashboardView.swift` — top-level SwiftUI view,
  branches on snapshot state, composes header/sections/footer.
- `Sources/Cursorcat/UI/DashboardComponents.swift` — `StatRow`,
  `QuotaRow`, `MonoBar`, `ErrorBanner`, `SectionHeader`, `PlanPill`.
- `Sources/Cursorcat/Support/Money.swift` — moved from `MenuBuilder.swift`.

## Edge cases

- **First launch, no snapshot yet.** Popover opens and shows the
  loading header; no jank, no empty sections.
- **Snapshot arrives while popover is open.** SwiftUI re-renders in
  place — `UsageStore` is already `ObservableObject` and `DashboardView`
  observes it.
- **User clicks Interact while the animator is mid-sequence.**
  Existing `animator.play(_:)` already interrupts cleanly. No change.
- **Popover open during right-click.** Close popover before popping up
  the actions menu so the user isn't staring at two surfaces at once.
- **Dark mode / light mode.** All colors are `.primary` /
  `.secondary` / `.tertiary` / material-aware — no hardcoded hex. Let
  the system invert.
- **Accessibility.** Each `QuotaRow` exposes
  `.accessibilityLabel("\(label), \(value)")` so VoiceOver reads "Auto,
  72 percent left" rather than describing the bar geometry.

## Implementation todos

- [ ] `shrink-menu` — Trim `MenuBuilder` to the actions-only menu,
  rename to `ActionsMenuBuilder`, move `Money` into `Support/`.
- [ ] `components` — Create `DashboardComponents.swift` with
  `StatRow`, `QuotaRow`, `MonoBar`, `SectionHeader`, `PlanPill`,
  `ErrorBanner`.
- [ ] `dashboard-view` — Create `DashboardView.swift` with the three
  state branches (loading / dashboard / logged-out) and the error
  banner. Wire to `UsageStore` via `@ObservedObject`.
- [ ] `popover-wiring` — In `StatusItemController`, swap
  `statusItem.menu = ...` for `NSPopover` + left/right click handler.
  Pass `DashboardActions` into the hosted view.
- [ ] `right-click-menu` — Keep the trimmed actions menu working on
  right-click via the `performClick` trick.
- [ ] `verify` — Build and run the app bundle (per `build-run-debug`
  skill). Confirm: left-click opens popover with correct data;
  right-click shows short action menu; quotas render monochrome bars;
  logged-out card appears when tokens absent; popover re-renders on
  poll; dark mode reads cleanly.

## Out of scope (later plans)

- A 7-day sparkline next to "Last 7 days" (Swift Charts; additive).
- A keyboard shortcut to open the popover from anywhere
  (`KeyboardShortcut` on a hidden command).
- A dedicated settings window (currently empty `Settings` scene).
