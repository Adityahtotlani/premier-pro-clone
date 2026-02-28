# PremierClone (Prototype)

A macOS-first open-source non-linear editor prototype inspired by Premiere Pro and Final Cut Pro.

## What is implemented

- Swift package architecture matching module boundaries:
  - `AppShell`
  - `ProjectCore`
  - `TimelineCore`
  - `PlaybackCore`
  - `RenderCore`
  - `AICore`
  - `IOAdapters`
- JSON project format with schema versioning (`schemaVersion = 3`)
- Migration support for previous schema versions (v1, v2)
- Autosave and recovery support from `autosaves/`
- Timeline operations:
  - insert
  - split
  - trim
  - move
  - ripple delete
  - deterministic mode switch (`track <-> magnetic`)
- Creator export preset registry and single-job render queue contract
- AI assist service contracts and heuristic artifact generation:
  - captions
  - silence removal suggestions
  - transcript search
  - smart reframe
  - highlight suggestions
- macOS SwiftUI app shell with source/program viewer placeholders, media bin, timeline panel, and top-level commands
- Project actions in app shell:
  - new/open/save/save-as project bundles
  - autosave timer and autosave recovery on open failure
  - media import dialog and proxy manifest generation
  - quick timeline edit actions (append selected asset, split at playhead, ripple delete selected clip)
  - keyboard command routing from app menus into the editor workspace
- Expanded pro workflow features:
  - startup home screen before entering timeline workspace
  - adaptive window scaling: compact layout stacks viewers and keeps toolbars/status usable via horizontal overflow
  - workspace layout system with Browser/Inspector panel toggles and Editing/Focused/Captions presets, persisted/restored via project settings
  - working quick actions for new/open/editor flow from home
  - multi-sequence create/duplicate/switch
  - timeline marker add + jump-to-next-marker
  - previous/next edit-point navigation
  - selectable timeline clips with live inspector editing (position/scale/opacity/gain)
  - linked A/V behavior for split, move, and ripple delete
  - transport controls (play/pause, frame step, start/end, 10s seek, playback speed cycle)
  - event viewer source controls (scrub, source in/out, clear in/out)
  - source-range timeline insert + append-to-end actions
  - working preview controls (viewer zoom in/out, mute + volume slider)
  - drag clips from Browser directly onto Timeline (drop-time insertion)
  - insert/overwrite timeline edit mode toggle
  - per-track timeline lanes with add/reorder/remove and target/mute/solo/lock controls
  - keyboard playback commands (`Space`, `,`, `.`, `Cmd+Left`, `Cmd+Right`)
  - JKL shuttle controls (`J` back step, `K` stop, `L` play/2x)
  - timeline keyboard controls for edit mode + track creation (`Cmd+Shift+W`, `Cmd+Opt+Shift+V/A`)
  - timeline in/out + loop shortcuts (`I`, `O`, `Cmd+Shift+X`, `Cmd+Shift+L`)
  - true time-mapped timeline ruler with click-to-seek and drag-to-move clip interactions
  - timeline index panel (markers, transcript search, silence suggestions)
  - caption generation + caption timeline lane + inline caption text editing
  - transcript jump-to-time and program-viewer live caption overlay
  - smart reframe presets (`9:16`, `1:1`, `16:9`) for selected video clips
  - simulated export progress with status + completion history

## Run tests

```bash
swift test
```

## Run app

```bash
swift run PremierCloneApp
```

## VS Code workflow

This repository includes a preconfigured `.vscode` setup:

- Build/debug tasks for `PremierCloneApp`
- `swift test` task
- Launch configs for debug/release
- Swift-focused workspace settings and extension recommendations

Open the folder in VS Code, install recommended extensions, then use:

- `Terminal -> Run Task -> swift: Build Debug PremierCloneApp`
- `Terminal -> Run Task -> swift: Test`
- `Run and Debug -> Debug PremierCloneApp`

## Project bundle format

Each project uses a bundle directory:

- `project.json`
- `autosaves/*.json`
- `cache/`

## Current status

This repository is a working prototype foundation (architecture + core services + tests + UI shell), not full Premiere/FCP parity.
