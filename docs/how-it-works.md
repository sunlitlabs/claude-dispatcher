# How it works

The problem: after a reboot, Windows has no record of which `claude` sessions were running, and Claude Code itself keeps no list of "open" sessions, only transcripts of every session ever run. So we keep our own list of live sessions, and use a heartbeat to tell *"was running when the machine went down"* from *"I closed that last week"*.

## Components

| File | Runs | Job |
| --- | --- | --- |
| `hook.ps1` | from Claude Code hooks | maintains the session registry |
| `heartbeat.ps1` | every minute (scheduled task) | proves which sessions are still alive |
| `resume.ps1` | at logon (scheduled task) | reopens sessions that were alive at shutdown |
| `dispatch.ps1` | on demand / first tab | menu to resume or start sessions |
| `launch.ps1` | dot-sourced | builds the Windows Terminal command line and the `claude` arguments (Remote Control) |
| `common.ps1` | dot-sourced | registry read/write helpers |

Everything is installed to `%USERPROFILE%\.claude\session-registry\`.

## The registry

One small JSON file per live session in `session-registry\sessions\<session-id>.json`: one file each avoids write conflicts between sessions.

```json
{
  "session_id": "d7ee4361-5e4d-4028-98b2-140edecafef7",
  "cwd": "C:\\Users\\me\\Development\\my-project",
  "pid": 1380,
  "pid_start": 134398361877513121,
  "started": "2026-11-22T16:01:58Z",
  "last_active": "2026-11-22T16:30:00Z",
  "ended_reason": null
}
```

`pid` is the `claude.exe` process (found by walking up the hook's parent processes). `pid_start` is that process's start time, so a recycled PID is never mistaken for the original.

## Hooks

| Event | `hook.ps1 -Event` | Effect |
| --- | --- | --- |
| `SessionStart` | `start` | write the entry; remove older entries owned by the same process (`/clear`, resume) |
| `Stop` | `stop` | bump `last_active` |
| `SessionEnd` | `end` | delete the entry on a deliberate exit; otherwise keep it and record the reason |

A `SessionEnd` with reason `prompt_input_exit`, `clear`, `logout` or `resume` is deliberate, so the entry is deleted and the session will not come back. Any other reason (window closed, OS shutdown) *keeps* the entry: during a shutdown Claude may get to run its end hook, and deleting the entry then would defeat the whole point. Whether a kept entry is resumed is decided by the heartbeat.

Hooks never block Claude Code: errors are logged to `hook-errors.log` and the hook always exits 0.

## The heartbeat

Every minute `heartbeat.ps1`:

1. for each entry whose `claude.exe` is still alive (PID + start time match), sets `last_active` to now
2. writes the current time to `heartbeat.txt`: a *global* heartbeat that stops ticking when the machine goes down, so its last value approximates the shutdown moment
3. deletes entries that have been dead for over 7 days

A session whose window you closed stops getting refreshed immediately, so its `last_active` falls behind.

## Resume at logon

`resume.ps1` runs once per boot:

1. Read the last global heartbeat (approximate shutdown time).
2. Select entries whose `last_active` is within 4 minutes of it, whose process is not alive, and whose folder still exists. These were alive at shutdown. Sessions closed earlier have an older `last_active` and are skipped.
3. Record this boot in `last-resume-boot.txt` so it never runs twice per boot, then clear the old entries. Resumed sessions re-register themselves through `SessionStart`.
4. Open one Windows Terminal window (`-w claude`) with a Dispatcher tab plus one `claude --resume <id>` tab per selected session, newest first, capped at 12.

`heartbeat.ps1` stays inert after boot until `resume.ps1` has handled that boot (or 15 minutes pass), so it cannot overwrite the evidence resume needs.

## The dispatcher

`dispatch.ps1` scans `%USERPROFILE%\.claude\projects\*\*.jsonl`, takes the most recent transcripts, and reads each one's first lines for the working directory and first real prompt, and its tail for the conversation title (`custom-title` from `/rename`, else `ai-title`). Transcripts whose entrypoint is `sdk-cli` (sub-sessions spawned by tools) are hidden. Running sessions come from the registry. Choosing an entry opens a tab (or runs inline with `h`) with `claude --resume <id>`.

## Resuming the same conversation

Plain `--resume <id>` continues the original session under the same ID; only the opt-in `--fork-session` creates a new one, and this tool never uses it. What can go wrong is the folder: a transcript lives at `projects\<key>\<id>.jsonl`, where `<key>` is the working directory with every non-alphanumeric character replaced by `-`, and `claude` only finds it when started from a folder with that key.

So both the dispatcher and `resume.ps1` call the helpers in `common.ps1` before launching:

1. `Find-Transcript` locates `<id>.jsonl`, first under the recorded folder's key, then across all projects.
2. `Resolve-ResumeCwd` collects the folders recorded in the transcript (plus the registry's) and picks one that exists and whose key matches the transcript's project directory.
3. If either step fails, nothing is launched: the dispatcher explains, `resume.ps1` logs a `skipped` line.

## Design notes

- **No Claude in the loop.** A "master session" that launches others would cost tokens and need resuming itself. A script and the registry do the same job deterministically.
- **Windows PowerShell 5.1 only.** No dependency on PowerShell 7, so it works on a stock machine.
- **Hidden scheduled tasks** run through `conhost.exe --headless` so no console window flashes every minute.
- **Atomic writes**: temp file + move, so a reader never sees a half-written entry.

## Known edge cases

- A session closed with the window's X and then followed by a reboot within a few minutes can still be resumed (its last heartbeat is inside the tolerance).
- A session whose `claude.exe` could not be found by the hook has no PID, so it cannot be heartbeated and will not be auto-resumed. The dispatcher can still resume it by hand.
- If the machine was powered off for a long time, the sessions that were alive at shutdown are still resumed. The comparison is against the last heartbeat, not against the current time.
