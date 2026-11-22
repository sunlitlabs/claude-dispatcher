# Troubleshooting

All state lives in `%USERPROFILE%\.claude\session-registry\`.

| File | What it tells you |
| --- | --- |
| `sessions\*.json` | sessions currently tracked |
| `heartbeat.txt` | last time the heartbeat task ran (UTC); should be under a minute old |
| `resume.log` | what each logon did and how many tabs it opened |
| `hook-errors.log` | errors from the hooks (absent means none) |
| `last-resume-boot.txt` | boot time that `resume.ps1` last handled |

## Nothing came back after a reboot

1. **Did anyone log in?** The resume task fires at logon, so a machine at the lock screen resumes nothing. See *Log in automatically* in the README.
2. Read `resume.log`. `resuming=0` means no entry qualified; `already handled this boot` means it ran earlier.
3. Check `heartbeat.txt` and the scheduled tasks:
   ```powershell
   Get-ScheduledTask ClaudeSession* | Get-ScheduledTaskInfo
   ```
   `LastTaskResult` should be `0`. If the heartbeat was not ticking before the reboot, the shutdown time was unknown and nothing could be resumed.
4. Was the session started *after* install? Earlier sessions are not registered.
5. Run `ls sessions` before rebooting. If your running sessions are not listed, the hooks are not firing (below).

## Preview what a logon would do

```powershell
powershell -File "$env:USERPROFILE\.claude\session-registry\resume.ps1" -DryRun -Force
```

This lists the sessions that would be resumed and changes nothing. `-Force` skips the once-per-boot check. Add `-ToleranceMinutes` or `-MaxTabs` to experiment.

To run the real thing without rebooting: `... resume.ps1 -Force`.

## Sessions are not being registered

- Check `settings.json` has `SessionStart`, `Stop` and `SessionEnd` entries pointing at `session-registry\hook.ps1`. Re-run `install.ps1` to restore them.
- Hooks load when a session starts, so restart the session after installing.
- Check `hook-errors.log`.
- Test a hook by hand:
  ```powershell
  '{"session_id":"00000000-0000-0000-0000-000000000001","cwd":"C:\\Temp"}' |
    powershell -NoProfile -File "$env:USERPROFILE\.claude\session-registry\hook.ps1" -Event start
  ```
  Then look in `sessions\` (and delete the test file afterwards).

## A session I closed came back

It was closed within a few minutes of the reboot, so its last heartbeat was inside the 4-minute tolerance. Exit with `/exit` for an immediate, certain removal.

## Tabs opened but a session said "no conversation found"

`claude --resume` looks up the transcript by the folder it is run from. The dispatcher and the reboot resume check this up front and refuse to open a tab that cannot work: the dispatcher says why, and `resume.log` records a `skipped <id>: transcript or matching folder not found` line. The usual cause is a moved, renamed or deleted project folder. Restore the folder at its original path and try again.

## The first Windows Terminal window is not where I expect

Tabs open in a window named `claude` (`wt -w claude`). Windows Terminal reuses that window if it already exists, so new tabs from the dispatcher land beside the resumed ones.

## Remove everything

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall -Purge
```
