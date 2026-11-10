# Releasing

## Build variants

```bash
./scripts/build-dmg.sh                    # universal, ad-hoc signed development DMG
./scripts/build-dmg.sh --clean            # clean build first
./scripts/build-dmg.sh --local-release    # Developer ID signed, not notarized
./scripts/build-dmg.sh --release          # signed and notarized
./scripts/build-dmg.sh --disable-updater  # strip Sparkle keys for a private build
./scripts/generate-appcast.sh             # sign the appcast after a release DMG
```

- Output goes to `release/`.
- Ad-hoc builds lose Accessibility permission on every rebuild; re-grant it.
- `--release` needs a local `Developer ID Application` certificate and notary credentials via
  `ASC_KEY_FILE` / `ASC_KEY_ID` / `ASC_ISSUER_ID` or a configured `ASC_1PASSWORD_ITEM`.
- With duplicate `Developer ID Application` names in the Keychain after a certificate rotation,
  resolve the certificate by SHA-1 hash before calling `codesign`.
- `xcrun stapler validate` is the reliable local notarization check. `spctl` can report
  `source=Insufficient Context` on a freshly stapled DMG that is in fact fine.
- The DMG places `LGTVMenuBar.app` on the left target and the Applications link on the right;
  preview the mounted DMG after changing `scripts/build-dmg.sh` or `scripts/assets/dmg-background.png`.

## Sparkle

- `Info.plist` carries the feed URL and public EdDSA key. `SoftwareUpdateController` starts
  Sparkle only when both are present, so UX-testing and `--disable-updater` builds never update.
- `generate-appcast.sh` signs with `SPARKLE_ED_PRIVATE_KEY`, `SPARKLE_PRIVATE_KEY_FILE`, or the
  Keychain account `com.thesammykins.lgtvmenubar`. Never print or commit the private key.
- Feed: `https://github.com/thesammykins/LGTVMenuBar/releases/latest/download/appcast.xml`.
- Keep `Package.resolved` committed.

## Steps

1. Run the scenarios in `docs/HARDWARE-VALIDATION.md`.
2. In `Sources/LGTVMenuBar/Info.plist`, add 1 to `CFBundleVersion` and set
   `CFBundleShortVersionString` (semver).
3. Complete the matching section of `CHANGELOG.md`; the tag workflow uses it as the release notes.
4. Validate on the branch:
   ```bash
   git push -u origin <branch>
   gh workflow run "Build and Release" --ref <branch> -f version=X.Y.Z
   gh run watch
   ```
   Branch runs upload `release/*.dmg` and `release/appcast.xml` as artifacts only.
5. Merge, then tag:
   ```bash
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```
   The tag run builds, notarizes and publishes the GitHub Release.

CI runs on the `xcode-27` runner image because the pinned dependencies need Swift 6.4 or
later; an older runner fails at package resolution.

CI needs these repository secrets: `ASC_CERTIFICATE`, `ASC_CERTIFICATE_PASSWORD`,
`ASC_PRIVATE_KEY`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`.

## Samantha's local install

```bash
./scripts/build-dmg.sh --disable-updater
```

Copy `release/LGTVMenuBar.app` over `/Applications/LGTVMenuBar.app` and confirm the updater keys
(`SUFeedURL`, `SUPublicEDKey`) are absent from its `Info.plist`.

## UX validation app

`./script/build_and_run.sh` builds `dist/UXTesting/LGTVMenuBarUXTesting.app` with
`UX_TESTING_APP` defined, a separate bundle id and no Sparkle metadata.

- `--snapshots` renders every view to `screenshots/snapshots/` with no extra permissions.
- `--verify` and `--screenshot` drive the window through System Events and need Accessibility
  and Screen Recording permission for the calling terminal.
- If a run is interrupted, quit only `LGTVMenuBarUXTesting`, never the production app.
