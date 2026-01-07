# Jabber

A macOS menu bar app for local speech-to-text transcription using [WhisperKit](https://github.com/argmaxinc/WhisperKit).

All audio is processed entirely on-device — nothing leaves your Mac.

## Requirements

- macOS 14.0+
- Apple Silicon recommended (Intel works but slower)

## Installation

Download the latest DMG from [Releases](../../releases), open it, and drag Jabber to Applications.

## Building from Source

```bash
swift build
```

For a release build with signing:

```bash
./scripts/release.sh --skip-notarize  # local testing
./scripts/release.sh                   # full signed + notarized DMG
```

## Usage

1. Launch Jabber — it lives in your menu bar
2. Click the icon or use the global hotkey to start dictation
3. Speak, and text appears wherever your cursor is

## License

MIT — see [LICENSE](LICENSE)
