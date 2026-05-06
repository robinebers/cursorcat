# Memory ownership

CursorCat is a long-running menu bar app, so each poll must leave behind only the small state needed to render the UI.

## Poll data

`CursorAPI.fetchSnapshot()` may temporarily hold large CSV exports. After `UsageStore.applySnapshot(_:)` projects that data into `UsageSnapshot`, the store keeps only projected snapshots for each `CostMode`. It must not retain raw `APISnapshot` or `[UsageCSVRow]` data between polls.

This keeps cost-mode switching instant without keeping every CSV row alive for the lifetime of the app.

## Debug data

Raw diagnostics should keep bounded previews, counts, and dates. Do not cache full CSV payloads or full RPC response bodies in long-lived actors unless a user explicitly enabled a bounded export flow.

## Timers and monitors

Owners of `Timer`, `DispatchSourceTimer`, `NSEvent` monitors, Combine subscriptions, or notification observers must provide a stop path that cancels or removes them. Closures should capture long-lived UI owners weakly unless the owner explicitly controls the lifetime.
