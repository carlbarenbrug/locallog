# Local Log

Local Log is a minimal and open-source macOS journaling app built for fast, frictionless capture. It lets you record both text and video entries in one quiet, focused space, with everything stored locally on your Mac for privacy and simplicity. No accounts, no cloud dependency, no clutter—just a clean archive of your thoughts, searchable and always yours. With autosave, editable entry titles, keyboard shortcuts, and light and dark mode support, Local Log is designed to stay out of the way so you can get straight to logging.

Design inspired by iA Writer and Freewrite.

## Current Scope

- Text journaling with autosave
- Video logging with local recording and playback
- Right-hand archive sidebar with search
- Editable entry titles backed by local filenames
- Autosave with debounce
- Keyboard shortcuts via app menu commands
- Light/dark UI support with dynamic Dock icon switching

## Requirements

- macOS 14+
- Xcode 16+

## Run Locally

1. Open `locallog.xcodeproj`
2. Select the `LocalLog` scheme
3. Build and run on `My Mac`

## Share Notarized Build

Distribute the signed and notarized archive:

- `dist/Local-Log-macOS.zip`
- GitHub Release: `https://github.com/carlbarenbrug/locallog/releases/latest`

## Data Storage

Entries are stored in:

`~/Documents/Local Log`

## Keyboard Shortcuts

- `Cmd+N` new entry
- `Cmd+R` start video entry
- `Cmd+H` toggle archive
- `Cmd+F` focus search
- `Cmd+Delete` delete selected entry
- `Cmd++` increase text size
- `Cmd+-` decrease text size
- `Cmd+0` reset text size
- `Ctrl+Cmd+F` toggle fullscreen

## License

This project is licensed under the MIT License. See `LICENSE`.
