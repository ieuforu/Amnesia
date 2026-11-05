# Amnesia

Give your AI amnesia. A macOS menu bar app to find and clear local Claude Code and Codex sessions.

> **Status: early development.** Deleting works, but there is no release yet, so build from source.

## Why

Coding agents keep every conversation on disk: transcripts, prompt history, file snapshots and logs. Deleting one transcript by hand usually leaves the rest behind, including the text you typed. Amnesia aims to show what is stored and remove it properly.

## Planned for v1

- List Claude Code CLI and Codex CLI sessions, grouped by project
- Show each session's time, size and first message
- Delete selected sessions, and skip any that are still running
- Find and clean up records of sessions that no longer exist

Desktop apps are out of scope for v1.

## What deleting does

| | Claude Code | Codex |
|---|---|---|
| Transcript | Moved to the Trash | Copy moved to the Trash |
| Other records | Removed for good | Removed for good by `codex delete` |
| Typed prompts in `history.jsonl` | Removed for good | Removed for good |
| Project memory | Never touched | Not applicable |

Transcripts stay on your Mac until you empty the Trash. Sessions that are running can't be selected, and each one is checked again just before it's deleted.

## Leftovers

Sessions removed by hand or by the agent's own cleanup often leave records behind, including the prompts you typed. Amnesia lists these under **Leftovers** and can remove them for good.

Anything touched in the last hour, and any running session, is left alone, and everything is scanned again just before cleaning. Project memory is never touched.

## Build from source

Requires macOS 14 or later and Xcode 16 or later.

```bash
scripts/build-app.sh
open .build/Amnesia.app
```

Run the tests with `swift test`.

To try it without touching real data, or to take screenshots, open it with made-up sessions:

```bash
open .build/Amnesia.app --args --demo
```

Nothing is read or deleted in demo mode.

## License

[MIT](LICENSE)

Amnesia is an independent project and is not affiliated with Anthropic or OpenAI.
