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
  - quick timeline edit actions (append first asset, split at playhead, ripple delete first clip)
  - keyboard command routing from app menus into the editor workspace

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
