# CursorCat

CursorCat is a tiny Mac app that lives in your menu bar and shows you how much you’re spending on Cursor today, with a little animated cat for company. No more popping open the Cursor website to check where you’re at, and a quick glance up at your menu bar tells you everything.

Click the cat and a small window drops down showing:

- What you’ve spent today, this week, or across your billing cycle
- How much of your quota you’ve used and when it resets
- Which AI models have been eating your budget

The cat itself reacts to what you’re doing. When you’re busy using Cursor, it scratches, runs around, and stays alert. When things are quiet, it yawns and curls up for a nap. It’s there to keep you company, not to stress you out.

## Who Is This For?

Anyone who uses Cursor and would rather not log into a dashboard just to check their usage. If you’ve ever wondered "wait, how much have I spent today?", this is for you.

## Requirements

- A Mac running macOS 26 (Tahoe) or newer
- Cursor already installed and signed in on your Mac

## Is This Official?

No. CursorCat is an unofficial companion app, made by a fan of Cursor. It doesn’t replace the Cursor app or website. It quietly reads the login you already have on your Mac and shows your usage in a friendlier place.

## Download

Grab the latest build from the [releases page](https://github.com/robinebers/cursorcat/releases/latest).

## Development Notes

- Local app bundles are staged with `./script/build_and_run.sh`.
- Release packaging is handled by `./script/package_release.sh`, which now defaults to `app` instead of a full notarize + DMG flow.
- `CODESIGN_IDENTITY` is required for release signing and notarization.
- Raw RPC/CSV payload logging is disabled by default. Set `CURSORCAT_LOG_RAW=1` only when you explicitly need verbose diagnostics.
- Xcode Debug uses `script/CursorCat.dev.entitlements.plist`; Release should not ship with that development entitlement.
- If you move or rename the repo directory, clear `.build/` before rebuilding so SwiftPM does not reuse stale module-cache paths from the old location.

## What Is The Cat?

The cat is a Neko-style desktop cat. Neko is a long-running cursor-chasing cat character that has been reimplemented on different platforms over the years. This repo bundles the `oneko.gif` sprite sheet from [adryd325/oneko.js](https://github.com/adryd325/oneko.js), which is licensed under MIT.

## Attribution

- Cursor auth and dashboard integration in this app was adapted from
  [robinebers/openusage](https://github.com/robinebers/openusage).
- The bundled cat sprite sheet comes from
  [adryd325/oneko.js](https://github.com/adryd325/oneko.js).
- Third-party notices are in [NOTICE](./NOTICE).
- The app itself remains an unofficial independent project.

## License

This repository is licensed under the [MIT License](./LICENSE).

Third-party material remains attributed in [NOTICE](./NOTICE).
