# Repo Notes

- `model_manifest.json`: when Cursor docs show `-` for cache write, set `cache_write_per_million` equal to `input_per_million` (not zero). Rates should match [Models & Pricing](https://cursor.com/docs/models-and-pricing); fast tiers may come from product UI when omitted from that table.
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

## Model Manifest Sync

Trigger when the user says something like "update models", "sync model manifest", "refresh model pricing", "check for new models", or "are any models missing". Goal: keep `Sources/CursorCat/Resources/model_manifest.json` aligned with Cursor's [Models & Pricing](https://cursor.com/docs/models-and-pricing) page.

- "update models" / "sync model manifest" → report gaps AND apply changes.
- "check for new models" / "are any models missing" → report only, do not edit.

### Source of truth

- Fetch `https://cursor.com/docs/models-and-pricing.md` (the `.md` form renders the pricing table as parseable text). Retry once on timeout — the endpoint can be slow.
- The docs "Model pricing" table is the source of truth for which models exist and their per-million-token rates.
- Compare docs → manifest only. The manifest intentionally holds entries NOT in the docs table (Cursor fast tiers like `composer-2-fast` / `gpt-5.5-fast`, `github_bugbot`, preview variants) because those come from the product UI or the notes column. Never delete manifest-only entries.

### Steps

1. Fetch the URL and parse the "Model pricing" table. For each row capture: display name, provider, input, cache write, cache read, output, notes.
2. Compare against `model_manifest.json` `pricing` keys. Report three categories:
   - **Missing models** — docs rows with no manifest entry (the actionable gaps).
   - **Price drift** — existing entries whose input / cache-read / output changed. Cache write is derived (see conventions), so don't flag it as drift.
   - **New providers** — a provider label not already in the manifest. Current set: `cursor`, `anthropic`, `google`, `openai`, `xai`, `moonshot`.
3. For each missing model, add a `pricing` entry and a matching `alias_rules` entry. No Swift code changes are needed: `provider` and `family_id` are free-form strings decoded by `Sources/CursorCat/Support/ModelManifest.swift`, and new families auto-group in `Sources/CursorCat/State/ModelBreakdown.swift`. Until a model is added, its usage shows in the app as an "unpriced" family with $0 estimated cost.
4. Bump `retrieved_at` to today's date (YYYY-MM-DD).
5. Update the hardcoded assertions in `Tests/CursorCatTests/ManifestAndModelBreakdownTests.swift` — see below.
6. Verify the manifest decodes and families resolve. Plain `swift test` does NOT work in this repo: the test bundle links `Sparkle.framework` and SwiftPM doesn't embed it into the `.xctest` bundle, so loading fails with `Library not loaded: @rpath/Sparkle.framework`. Build the tests, embed Sparkle, and run the bundle directly:
   ```
   swift build --build-tests
   XCT=.build/out/Products/Debug/CursorCatTests.xctest
   mkdir -p "$XCT/Contents/Frameworks"
   cp -R .build/out/Products/Debug/Sparkle.framework "$XCT/Contents/Frameworks/"
   xcrun xctest -XCTest ManifestAndModelBreakdownTests "$XCT"
   ```
   (If `swift build --show-bin-path` reports a different directory, adjust `$XCT` and the Sparkle source path to match.) Then `./script/build_and_run.sh` to build the full app bundle — which embeds Sparkle itself — and launch it.

### Manifest conventions

- **Keys**: lowercase, hyphenated, version dots preserved (e.g. `glm-5.2`, `gpt-5.4-mini`).
- **cache_write_per_million**: when docs show `-`, set it equal to `input_per_million` (NOT zero). When docs give an explicit cache-write price (Anthropic models), use that.
- **provider**: free-form lowercase string; use the docs' provider label lowercased (e.g. Z.ai → `zai`). No registry to update.
- **family_id / family_display_name**: for a single-variant model, both equal the key and the display name respectively. For fast / preview variants of a base model, reuse the base model's `family_id` and `family_display_name` so they roll up together (see `composer-2` vs `composer-2-fast`).
- **apply_max_mode_uplift**: NOT in the docs table. Match the prevailing value for the model's family; for a brand-new provider default to `true` and flag it for human confirmation.
- **long_context_***: add the four `long_context_input_threshold` / `long_context_input_multiplier` / `long_context_output_multiplier` / `long_context_cached_input_multiplier` fields only when the notes say pricing multiplies above a token threshold (e.g. "2x when input exceeds 200k tokens"). Copy the threshold and multipliers from the notes; if unspecified, omit the fields. (Note: `Pricing.estimatedCostDollars` does not apply these to CSV aggregates, so they're metadata for now.)
- **alias_rules**: add a regex that matches the model string Cursor emits in usage CSV. Anchor with `^...$` and escape literal dots as `\\.`. Mirror existing rules for the same family (reasoning-effort suffixes `-low|-medium|-high|-xhigh|-max`, `-thinking`, `-fast`, `-preview`). First match wins, so place more-specific rules before broader ones and never add a rule that shadows an existing tested string (see `testPricingResolvesModelFamily`).
- **Premium routing** is not a model — handle it via `alias_rules` mapping a `Premium (X)` string to a canonical model, like the existing `^[Pp]remium \\((?:[Gg][Pp][Tt]-5\\.3-[Cc]odex|[Cc]odex 5\\.3)\\)$` → `gpt-5.3-codex` rule. Cursor-internal aliases (`default` → `auto`, `agent_review` → `gpt-5.4`, `github_bugbot`) must be preserved.

### Test update (required)

`Tests/CursorCatTests/ManifestAndModelBreakdownTests.swift` hardcodes manifest values, so editing the manifest usually requires editing the test in the same change:

- Always update `XCTAssertEqual(manifest.retrievedAt, "2026-06-09")` to the new `retrieved_at`.
- If you changed a price for any model asserted in `testBundledManifestLoadsFamilyMetadata`, update that assertion too. Asserted models: `claude-4.7-opus`, `claude-4.8-opus`, `claude-4.8-opus-fast`, `claude-fable-5`, `gpt-5.5`, `gpt-5.5-fast`, `composer-2.5`, `composer-2.5-fast`, `grok-4.3`, `grok-build-0.1`, `gemini-3.5-flash`.
- Adding a brand-new model (e.g. `glm-5.2`) needs no new test assertion beyond the `retrievedAt` bump, though adding a `Pricing.family(for: "glm-5.2")` line to `testPricingResolvesModelFamily` is good coverage.

### Example: adding GLM 5.2

Docs row: `GLM 5.2 | Z.ai | $1.4 | - | $0.26 | $4.4`. Cache write is `-`, so it equals input. Cursor's CSV emits effort variants like `glm-5.2-max`, so the alias regex below allows an optional `-thinking` then an optional effort suffix (`-low|-medium|-high|-xhigh|-max`) — mirror this suffix pattern for any new model that ships reasoning-effort variants.

```json
"glm-5.2": {
  "display_name": "GLM 5.2",
  "provider": "zai",
  "family_id": "glm-5.2",
  "family_display_name": "GLM 5.2",
  "input_per_million": 1.4,
  "cache_write_per_million": 1.4,
  "cache_read_per_million": 0.26,
  "output_per_million": 4.4,
  "apply_max_mode_uplift": true
}
```

```json
{ "pattern": "^glm-5\\.2(?:-thinking)?(?:-(?:low|medium|high|xhigh|max))?$", "canonical": "glm-5.2" }
```
