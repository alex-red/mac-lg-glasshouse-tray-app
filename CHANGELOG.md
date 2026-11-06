# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0]

### Added
- The tray menu shows whether Accessibility access is working for the volume
  keys, with a shortcut to the setting and a Restart item when it isn't.
- Install with Homebrew: `brew install --cask alex-red/tap/glasshouse-tray`.

### Fixed
- The volume keys go back to controlling the TV after the Mac sleeps or the
  display turns off, instead of falling back to the Mac's own volume.

## [0.1.0]

### Added
- The Mac's volume keys control the TV's volume while it is the audio output.
  - Shift-Option with a volume key moves a single step.
  - An on-screen display shows the TV's level.
- Tray menu:
  - Volume slider and mute.
  - Screen off/on, and power off/on (Wake-on-LAN when the TV is fully off).
  - Input, Sound Output and Picture Mode submenus.
  - Play/Pause, and a link to the Glasshouse dashboard.
- Settings for the TV address, port, API token and volume step, and an
  option to open at login.
- App icon.
- GitHub Actions for CI builds and tagged releases.

[Unreleased]: https://github.com/alex-red/mac-lg-glasshouse-tray-app/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/alex-red/mac-lg-glasshouse-tray-app/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/alex-red/mac-lg-glasshouse-tray-app/releases/tag/v0.1.0
