# Development

[English README](../README.md) · [한국어 README](../README.ko.md)

Serein is a SwiftPM macOS application using SwiftUI, AppKit, Core Graphics, Vision, EventKit, and ServiceManagement. It has no third-party package dependencies.

## Build and signing

Run `./scripts/build-app.sh` from the repository root. The app is written to `dist/Serein.app`; the script also generates the icon and verifies its signature. Builds are local development builds, not notarized releases.

The first build creates a signing identity under `~/Library/Application Support/SereinDevelopmentSigning/identity`. Later builds reuse it. Keep this directory to preserve identity between updates, and never commit its keychain, keys, or password files. The script does not change system certificate trust and removes its temporary keychain search-list entry when it finishes.

To use your own Apple development identity, set `SEREIN_SIGN_IDENTITY` and, optionally, `SEREIN_SIGN_KEYCHAIN` before running the script.

## Verification

The standalone checks work with Command Line Tools:

```sh
./scripts/verify-renderer.sh
./scripts/verify-weekday-labels.sh
./scripts/verify-ocr.sh
./scripts/verify-calendar.sh
./scripts/verify-automation.sh
./scripts/verify-calendar-recovery.sh
./scripts/verify-calendar-visibility.sh
./scripts/verify-calendar-visibility-app.sh
./scripts/verify-spaces.sh
python3 scripts/verify-signing.py
```

`swift test` additionally requires an Xcode environment with XCTest. Tests use fixtures and fake calendar providers; native permissions and all-Space behavior need macOS integration checks. See the [development log](devlog.md) for checks actually run at each milestone.

## Rebuild the README gallery

```sh
./scripts/render-gallery.sh
```

This calls the production wallpaper renderer at 3840 × 2160 with fixed, fictional schedules. It writes high-quality JPEG previews to `docs/images` without upscaling. App exports remain lossless PNG. No calendar access, saved-work loading, or wallpaper changes occur.

## Try the UI with example calendars

Quit an existing Serein instance first, then run either command:

```sh
open dist/Serein.app --args --calendar-demo
open dist/Serein.app --args --automation-demo
```

Demo mode uses fictional calendars and does not save over personal work. Automation writes only a temporary sample PNG. Quit and reopen without arguments to return to normal mode.

## Compatibility and local data

- Calendar integration reads macOS-synced accounts through EventKit; there is no separate Google OAuth flow.
- OCR results need review, especially with blurry images or tables lacking explicit time labels.
- The all-Spaces path supports known macOS 14, 15, and 26 wallpaper-store formats. It backs up before writing and refuses unknown formats. This is not a public Apple API.
- Work is stored under `~/Library/Application Support/Serein/`; applied images and wallpaper-store backups stay there too. These are user data, not repository artifacts.
- Rendering is deterministic for the same input, explicit date labels, settings, and macOS/font environment.

## Prompt-linked history

Original requests live in [docs/prompts](prompts), results in [devlog.md](devlog.md), and milestone commits carry `Prompt-ID` trailers. The public history retains the original commits and author metadata, as requested. Repository visibility and publishing history are documented in the [publication review](publication-review.md).
