# Shhhazam 🤫

A tiny macOS menu-bar utility that warns you when you're talking too loudly, so you don't annoy everyone else in the office.

It watches the level of your **current system microphone** and, once you stay above a threshold you set for long enough, fires a system notification. Set the limit, forget it's there, and let it nudge you when your voice creeps up.

<img width="751" height="351" alt="Shhhazam app" src="https://github.com/user-attachments/assets/348b240b-b32e-4d3f-ac8d-072fff666fe8" />

## Features

- **Lives in the menu bar** — no Dock icon, no window to manage. The glyph changes when you're over the limit.
- **Combined level + threshold slider** — the bar fill is your live mic level (green, turning red when over); the draggable knob is the alert threshold (in dBFS).
- **Sustain window** — only alerts after you're continuously over the threshold for a set time (default 2s), so a cough or sneeze won't trigger it.
- **Keeps nagging** — if you stay loud, it re-alerts every 10× the sustain time; once you drop back below, it re-arms for the next time you start speaking.
- **Follows your mic** — reads the current default input and switches automatically when the default device changes (e.g. popping in AirPods before a call).
- **Launch at login** — optional toggle.
- **Private by design** — it only measures the input *level*. Audio is never recorded or transmitted.

## Requirements

- macOS 15.7 or later
- Xcode 16 or later (with the command-line tools selected via `xcode-select`)

## Build from the command line

```sh
git clone git@github.com:daveharris/Shhhazam.app.git
cd Shhhazam.app

xcodebuild \
  -project Shhhazam.xcodeproj \
  -scheme Shhhazam \
  -configuration Release \
  -derivedDataPath build \
  build
```

The signed app is written to:

```
build/Build/Products/Release/Shhhazam.app
```

Launch it with:

```sh
open build/Build/Products/Release/Shhhazam.app
```

On first launch macOS will ask for **microphone** and **notification** permission — both are required for it to do anything useful.

> **Tip:** to run it every day, enable **Launch at login** in the popover, or move `Shhhazam.app` into `/Applications`.
