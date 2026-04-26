# Repo Notes

- App icons: `Resources/AppIcon/AppIcon.icon` is consumed by Xcode, not by the shell bundle scripts. For script-built `.app` bundles, keep `Resources/AppIcon/AppIcon.icns` and `Resources/AppIcon/Assets.car` in sync with Xcode's compiled outputs and copy them into the bundle; also set `CFBundleIconFile=AppIcon` and `CFBundleIconName=AppIcon`.
- Xcode Debug uses `script/CursorCat.dev.entitlements.plist`; Release should not.
- If the repo path changes, clear `.build/` before rebuilding so SwiftPM does not reuse module-cache paths from the old location.
- `package_release.sh` defaults to `app` mode, not a full release flow. Use `release` for the full flow.

## Task Actions

Prefer these canonical scripts over improvising new commands. They are also surfaced as one-click actions in `.codex/environments/environment.toml`; the table below is the source of truth and applies to every agent, not just Codex.

| Action | Command |
| --- | --- |
| Build and Run | `./script/build_and_run.sh` |
| Build Only | `./script/build_and_run.sh --build` |
| Debug | `./script/build_and_run.sh --debug` |
| Logs | `./script/build_and_run.sh --logs` |
| Telemetry | `./script/build_and_run.sh --telemetry` |
| Verify Launch | `./script/build_and_run.sh --verify` |
| Package App | `./script/package_release.sh app` |
| Notarize App | `./script/package_release.sh notarize-app` |
| Build DMG | `./script/package_release.sh dmg` |
| Local Release Artifact | `./script/package_release.sh release` |
| Publish GitHub Release | `./script/publish_release.sh` |

## Environment Variables

- `CURSORCAT_LOG_RAW=1` — enable raw RPC/CSV payload logging (off by default; diagnostics only).
- `CODESIGN_IDENTITY` — required for release packaging (Developer ID Application). Local dev builds auto-discover an Apple Development identity or fall back to ad-hoc signing.
- `NOTARY_PROFILE` — overrides the `notarytool` keychain profile name (default `notarytool-profile`).
- `APP_VERSION` / `APP_BUILD` — override bundle version metadata for `package_release.sh`.
- `SPARKLE_PUBLIC_ED_KEY_FILE` / `SPARKLE_PRIVATE_KEY_FILE` / `SPARKLE_PUBLIC_ED_KEY` — override Sparkle key discovery (defaults `~/.cursorcat/sparkle/public_ed_key.txt` + `~/.cursorcat/sparkle/private_ed25519.pem`).

## Release Flow

Use `./script/publish_release.sh` as the canonical release path. Do not manually invent version numbers from checked-in defaults such as `project.yml`, `build_and_run.sh`, or `package_release.sh`; those can lag behind the public release. The release script resolves the next patch from the latest `vX.Y.Z` git tag unless the user provides an explicit `vX.Y.Z`.

When the user asks to create a patch release/version and does not specify a version:

1. Confirm the latest public version from tags or GitHub releases, then use the next patch version.
2. Run the existing release script rather than hand-rolling steps: `./script/publish_release.sh` for a real release, or `./script/publish_release.sh --dry-run` when validating only.
3. The release flow must build, sign, notarize, create the DMG/app bundle artifact, create/push the version tag, create the GitHub release with `gh`, upload the artifact, and publish the Sparkle appcast.
4. Do not run `publish_release.sh` without an explicit user request, because it pushes a tag and publishes publicly.

Flags:

- `vX.Y.Z` — explicit version; otherwise the script uses the next patch version from the latest release tag.
- `--dry-run` — prints what would happen without tagging/pushing/releasing.
- `--skip-package` — reuses the existing `dist/release/` artifact.
- `--allow-dirty` — bypasses the clean-worktree check.

Requirements: clean worktree, `gh auth status` OK, valid `CODESIGN_IDENTITY`, accessible `NOTARY_PROFILE`, Sparkle keys on disk. On failure the script prints exact cleanup commands.
