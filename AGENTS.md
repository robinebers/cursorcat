# Repo Notes

- Next.js 16+: `middleware.ts` is now `proxy.ts`.
- Use `bun`/`bunx`, never `npm`/`npx`.
- Do not run the dev server or build unless explicitly asked.
- Do not create or update README/docs/markdown plans unless explicitly asked.
- App icons: `Resources/AppIcon/AppIcon.icon` is consumed by Xcode, not by the shell bundle scripts. For script-built `.app` bundles, keep `Resources/AppIcon/AppIcon.icns` and `Resources/AppIcon/Assets.car` in sync with Xcode’s compiled outputs and copy them into the bundle; also set `CFBundleIconFile=AppIcon` and `CFBundleIconName=AppIcon`.

## Running Locally

The main local entrypoint is:

```bash
./script/build_and_run.sh
```

Supported modes:

- `./script/build_and_run.sh`
- `./script/build_and_run.sh --build`
- `./script/build_and_run.sh --debug`
- `./script/build_and_run.sh --logs`
- `./script/build_and_run.sh --telemetry`
- `./script/build_and_run.sh --verify`

Notes:

- The script stages a local `.app` bundle into `dist/`.
- If an Apple Development signing identity is available, the script uses it.
- If no signing identity is available, it falls back to ad-hoc signing.

## Packaging A Release

Release packaging is handled by:

```bash
./script/package_release.sh
```

Supported modes:

- `./script/package_release.sh app`
- `./script/package_release.sh notarize-app`
- `./script/package_release.sh dmg`
- `./script/package_release.sh release`

Optional environment variables:

- `CODESIGN_IDENTITY` to override the signing identity
- `NOTARY_PROFILE` to override the `notarytool` keychain profile name
- `APP_VERSION` and `APP_BUILD` to override bundle version metadata
