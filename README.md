# Local Log

Local Log is a local-first macOS journal app focused on fast capture with minimal UI friction.

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
