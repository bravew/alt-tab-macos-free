# AltTab Free — fork notes

A personal fork of [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos)
that keeps every feature unlocked. AltTab is **GPL-3.0**, including its Pro code,
so modifying and rebuilding it is within the rights the license grants.

> This is for **personal use**. Don't redistribute it publicly under the "AltTab"
> name (trademark). If AltTab earns a spot in your workflow, consider supporting
> the developer — the Pro code being open source is why this fork is a few lines.

## What's patched

Four small, self-contained changes on top of upstream:

| File | Change |
|------|--------|
| `src/pro/license/LicenseManager.swift` | `computeState()` always returns `.pro` — single source of truth, so all gates/nags/badges resolve to Pro. No server call (none happens without a license key). |
| `src/vendors/SparkleDelegate.swift` | `feedURLString` returns `nil` — disables the auto-updater so it can't replace this build with the upstream paywalled release. |
| `config/base.xcconfig` | `PRODUCT_BUNDLE_IDENTIFIER` → `com.lwouis.alt-tab-macos.free` — distinct identity so it coexists with an official AltTab and gets its own permission entries. |
| `Info.plist` | `CFBundleName` / `CFBundleDisplayName` → "AltTab Free". |

## Build & install locally

```bash
./update.sh            # latest upstream, rebuilt + installed to /Applications
./update.sh 8.4.0      # force a version string
```

`update.sh` merges `upstream/master`, rebuilds (Release), stamps the version
(upstream leaves it blank, which crashes on launch), code-signs, and swaps the
app into `/Applications/AltTab Free.app`.

### Permissions

AltTab needs **Accessibility** (for the ⌥Tab hotkey) and, for window thumbnails,
**Screen Recording**. Signing each build with the *same* identity keeps these
grants across updates — set `ALTTAB_SIGN_ID` in `update.sh` to a code-signing
identity from `security find-identity -v -p codesigning`. With ad-hoc signing
(`ALTTAB_SIGN_ID=""`) you re-grant after each update.

## CI / `.dmg`

`.github/workflows/build-dmg.yml` builds the patched app on a macOS runner and
produces an **unsigned `.dmg`** as a workflow artifact (and attaches it to
GitHub Releases). Unsigned means recipients do a **one-time right-click → Open**
to clear Gatekeeper. (Zero-warning distribution would need a paid Apple
Developer ID + notarization.)

The upstream `ci_cd.yml` pipeline is disabled on this fork (it needs signing
secrets we don't have); we don't edit it, to avoid merge conflicts on update.

## Staying current

Upstream rarely touches the patched lines, so `./update.sh` merges cleanly.
If a conflict appears, resolve those few lines, `git commit`, and re-run.
