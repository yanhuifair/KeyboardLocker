# Changelog

## Unreleased

- `release.sh`: one-command publishing — version bump, changelog-based notes, build, tag and GitHub Release
- `build.sh`: `KEYBOARDLOCKER_ADHOC=1` forces an ad-hoc signature for distribution builds
- README: promo banner (`docs/promo.png`) covering the title, features and safety highlights

## 1.0.0 — 2026-11-04

First release.

- Menu bar toggle that locks every key on the keyboard, including modifiers and media keys
- Red solid icon while locked, outlined white keyboard when idle
- Screen lock / display sleep / system sleep auto-unlock, backed by a once-per-second session check
- Refuses to lock while the screen is already locked
- Modifier keys released on unlock so ⌘/⇧/⌥/⌃ never stay stuck
- `--selftest` command-line verification
