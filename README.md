# Amnesia

Give your AI amnesia. A macOS menu bar app to find and clear local Claude Code and Codex sessions.

> **Status: early development.** The app launches, but scanning and deleting are not implemented yet.

## Why

Coding agents keep every conversation on disk: transcripts, prompt history, file snapshots and logs. Deleting one transcript by hand usually leaves the rest behind, including the text you typed. Amnesia aims to show what is stored and remove it properly.

## Planned for v1

- List Claude Code CLI and Codex CLI sessions, grouped by project
- Show each session's time, size and first message
- Delete selected sessions, and skip any that are still running
- Find leftovers whose session is already gone

Desktop apps are out of scope for v1.

## Build from source

Requires macOS 14 or later and Xcode 16 or later.

```bash
scripts/build-app.sh
open .build/Amnesia.app
```

Run the tests with `swift test`.

## License

[MIT](LICENSE)

Amnesia is an independent project and is not affiliated with Anthropic or OpenAI.
