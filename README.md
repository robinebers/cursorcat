# Cursorcat

Cursorcat is a native macOS menu bar app for keeping an eye on your Cursor usage
without living in the dashboard. It shows current spend and usage state in the
menu bar next to a small animated cat, then opens a compact popover with billing
cycle, model breakdown, and quota details.

## What Is The Cat?

The cat is a Neko-style desktop cat. Neko is a long-running cursor-chasing cat
character that has been reimplemented on different platforms over the years. This
repo bundles the `oneko.gif` sprite sheet from
[adryd325/oneko.js](https://github.com/adryd325/oneko.js), which is licensed
under MIT.

## Attribution

- Cursor auth and dashboard integration in this app was adapted from
  [robinebers/openusage](https://github.com/robinebers/openusage).
- The bundled cat sprite sheet comes from
  [adryd325/oneko.js](https://github.com/adryd325/oneko.js).
- Third-party notices are in [NOTICE](./NOTICE).

## License

This repository is licensed under the [MIT License](./LICENSE).

Third-party material remains attributed in [NOTICE](./NOTICE).

## Notes

This is an unofficial Cursor companion app. It reads local Cursor auth state and
calls the same Cursor endpoints the app uses for its dashboard and billing data.
