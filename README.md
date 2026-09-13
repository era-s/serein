# Serein

**Your week, in a new light.**

English · [한국어](README.ko.md)

Turn a timetable or calendar into a thoughtfully designed Mac wallpaper. Native macOS, on-device OCR, and graphics drawn entirely in code. No generative images. No API keys.

[![Ember wallpaper with real dates and a subtle today border](docs/images/ember.jpg)](docs/images/ember.jpg)

## Make it yours

| Start with | Finish with |
| --- | --- |
| A timetable image | Recognize text locally, then review and edit. |
| A few entries you type | Adjust subjects, times, places, and your own headline. |
| Apple Calendar or Google Calendar¹ | Import a week; hide events without changing the original calendar. |
| Your favorite design | Export a full-resolution PNG or apply it to all desktops and displays. |

¹ Google Calendar connects through the accounts synced to the macOS Calendar app. The app interface is currently in Korean.

## Three colors. Plenty of room.

**Ember** above, **Moss** and **Midnight** below. Every image on this page is a fresh **3840 × 2160** render with fictional events. Click to open at full resolution.

| Moss | Midnight |
| :---: | :---: |
| [![Moss — olive green](docs/images/moss.jpg)](docs/images/moss.jpg) | [![Midnight — deep blue](docs/images/midnight.jpg)](docs/images/midnight.jpg) |

| A full weekend | Just the essentials | When plans overlap |
| :---: | :---: | :---: |
| [![Seven-day calendar with Saturday highlighted](docs/images/weekend.jpg)](docs/images/weekend.jpg) | [![Minimal schedule with weekday numbers hidden](docs/images/quiet.jpg)](docs/images/quiet.jpg) | [![Korean and English events with overlapping sessions](docs/images/overlap.jpg)](docs/images/overlap.jpg) |

Choose real day numbers (`07`, `08`), sequential numbers (`01`, `02`), or no numbers. Change the headline, show locations, and include weekends.

## A fresh week, automatically

Three independent options, all off by default:

- **Calendar changes:** refresh when the selected calendars’ current-week events change.
- **Weekly refresh:** switch to the new week on Monday, or catch up when the app resumes.
- **Today:** add a subtle border that moves with the date.

Hidden recurring events stay hidden through sync and future weeks. Serein keeps working in the menu bar after its window closes; quitting the app stops updates. Launch at login is optional.

## Run on your Mac

Requires **macOS 14+**, **Swift 5.10+**, and Apple’s Command Line Tools. No third-party package dependencies.

```sh
git clone https://github.com/era-s/serein.git
cd serein
./scripts/build-app.sh
open dist/Serein.app
```

This builds locally; it is **not a notarized release**. The build script creates a persistent local signing identity so later builds retain the same app identity. [Build details and checks →](docs/DEVELOPMENT.md)

## Local by design

OCR runs through Apple Vision. Serein does not upload your images or schedules to a server. Calendar access is read-only in the app, even though macOS calls the permission “Full Access.” Calendar providers still handle their own account sync.

Review OCR results before applying them. Applying to every Space uses a backed-up, version-checked macOS wallpaper-store format; future macOS changes may require compatibility updates. PNG export remains available.

[Detailed guide (한국어)](docs/guide.ko.md) · [Development history](docs/devlog.md) · [Publication privacy review](docs/publication-review.md)
