# Local Log (macOS)

## Install
1. Download `Local-Log-macOS-unsigned.zip`.
2. Unzip it.
3. Move `Local Log.app` to `Applications`.
4. Open Terminal and run:

```bash
xattr -dr com.apple.quarantine "/Applications/Local Log.app" && open "/Applications/Local Log.app"
```

## Notes
- This build is unsigned/not notarized, so macOS may show a security warning.
- All journal data is stored locally under your sandboxed Documents container for the app.
