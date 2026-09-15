# Notchy

Native macOS Dynamic Island–style app for the MacBook notch.

Full design/rationale: [docs/RESEARCH.md](docs/RESEARCH.md). Stack, architecture
rules, and progress: [CLAUDE.md](CLAUDE.md).

## Build & run

```sh
xcodegen generate
xcodebuild -scheme Notchy -configuration Debug build | xcbeautify
xcodebuild -scheme Notchy test | xcbeautify
```

Or open `Notchy.xcodeproj` in Xcode after `xcodegen generate` and run.

## Format & lint

```sh
swiftformat .
swiftlint
```
