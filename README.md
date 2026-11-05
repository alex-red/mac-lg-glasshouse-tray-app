# Glasshouse Tray

A small, native macOS menu bar app for LG webOS TVs running
[Glasshouse](https://github.com/rorygallagher2024/glasshouse).

When the TV is your Mac's audio output over HDMI, macOS can't change its
volume: the volume keys just show a "no entry" sign. Glasshouse Tray picks up
those keys and sets the TV's volume instead, with its own on-screen level
display. The menu also covers the everyday controls.

## Features

- **Volume keys control the TV.** Volume up, down and mute go to the TV while
  it is the default output, and work normally for every other device.
  - Shift-Option with a volume key moves a single step.
  - Holding a key down is coalesced into a handful of requests.
  - Outputs that can't be set to a level (e.g. an eARC soundbar) get
    remote-key steps instead.
- **Volume slider and mute** in the menu.
- **Screen off / on.** Blanks the OLED but keeps the picture signal and audio
  running, which is handy when the TV is a Mac display.
- **Power off / on.** Uses Wake-on-LAN when the TV is fully off.
- **Input, sound output and picture mode**, listed from what the TV reports
  (including the names you gave your inputs).
- **Play / Pause**, and a shortcut to the Glasshouse web dashboard.

It's built to stay out of the way:
- AppKit only, with no SwiftUI runtime and no web view.
- No polling while the menu is closed.
- The key tap is only active while the TV is the audio output.

## Requirements

- An Apple silicon Mac on macOS 14 or later.
- An LG TV with Glasshouse installed and reachable on the local network (by
  default on port 8080). Glasshouse needs a rooted TV with the Homebrew
  Channel; see its docs.

## Build

Requires Xcode (or the Swift 6 toolchain).

```sh
make app       # builds build/GlasshouseTray.app
make run       # builds and opens it
make install   # copies it to /Applications
```

The app is signed with the first "Apple Development" or "Developer ID
Application" identity in your keychain. Without one it is signed ad hoc, which
works, but macOS forgets the Accessibility permission on every rebuild. To
choose an identity yourself:

```sh
make app SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"
```

## Setup

1. Open the app. A TV icon appears in the menu bar.
2. Open **Settings…** and enter the TV's address. Add the API token if one
   is set in Glasshouse.
3. The first time the TV is the audio output, macOS asks for
   **Accessibility** access. The app needs it to intercept the volume keys.
   Allow it in System Settings › Privacy & Security › Accessibility.
4. macOS may also ask for **Local Network** access. Allow it.

### Which audio output counts as the TV

By default, any HDMI or DisplayPort output whose name contains "LG" counts as
the TV. If yours is named differently:
1. Select it as the output.
2. Choose **Use "…" as the TV** from the menu.

## How it works

Glasshouse runs a small HTTP server on the TV. This app uses three of its
endpoints:

| Endpoint | Used for |
| --- | --- |
| `GET /api/caps` | Checking the server is there |
| `GET /api/stats` | Volume, mute, power, input, sound output and picture mode |
| `POST /api/control` `{"action", "value"}` | Every command (`volume`, `volumeStep`, `mute`, `screenOff`, `input`, …) |

Glasshouse has no push channel over HTTP, so the app reads `/api/stats` when
it needs fresh state:
- every 2 s while the menu is open
- before the first key press after 10 s idle

Volume keys come in as `NSSystemDefined` events. A session `CGEventTap` sees
them before the system handles them. A CoreAudio listener on the default
output device switches the tap on and off.

## License

MIT, see [LICENSE](LICENSE). Not affiliated with LG Electronics.
