# claude-dispatcher

Get your [Claude Code](https://claude.com/claude-code) sessions back after Windows restarts, and start or resume sessions from a single control tab. Built for machines you use remotely, where nobody is at the keyboard to reopen terminals after an update reboot.

- **Auto-resume.** After a reboot, every session that was running comes back, each in its own folder, via `claude --resume`. Nothing is hardcoded; whatever you were running last time is what returns.
- **Respects what you closed.** A session you exited on purpose, or whose window you closed earlier, stays closed.
- **Dispatcher tab.** A menu listing your recent sessions. Pick one to resume it, or start a fresh session in any folder. Run it any time with `cdispatch`.

Windows 10/11, Windows PowerShell 5.1 (already installed), Windows Terminal, Claude Code. No admin rights needed.

## Install

```powershell
git clone https://github.com/sunlitlabs/claude-dispatcher
cd claude-dispatcher
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

This will:

1. copy the scripts to `%USERPROFILE%\.claude\session-registry\`
2. add three hooks (`SessionStart`, `Stop`, `SessionEnd`) to `%USERPROFILE%\.claude\settings.json`, after backing it up to `settings.json.bak-claude-dispatcher`. Existing hooks are kept.
3. register two scheduled tasks for your user: `ClaudeSessionResume` (at logon) and `ClaudeSessionHeartbeat` (every minute)
4. put `cdispatch.cmd` in `~\.local\bin` or `~\bin` if either is on your `PATH`

Sessions that were already running are not tracked. Restart each one once so the hooks register it. Re-run `install.ps1` after a `git pull` to upgrade.

**Log in automatically after a reboot.** The resume task fires at logon. If the machine sits at the lock screen after restarting, nothing resumes until you sign in (for example over RDP). To make it fully hands-off, enable automatic sign-in, for instance with Sysinternals [Autologon](https://learn.microsoft.com/sysinternals/downloads/autologon). That stores your password on the machine, so weigh that against your physical-security situation. This repo does not set it up for you.

## Using it

### After a reboot

At logon, a single Windows Terminal window named `claude` opens:

| Tab | Contents |
| --- | --- |
| `Dispatcher` | the menu below |
| one per session | `claude --resume <id>` in the session's original folder |

At most 12 session tabs are reopened.

### The dispatcher

Run `cdispatch` in any terminal, or use the first tab after a reboot.

```
Claude dispatcher
  [number] resume in tab   [number]h resume here   n new   r refresh   q quit

  1    0m  my-project          Is there a way to make my sessions all resume when...
  2   16m  other-project       Are we up?
  3    4d  my-project          You can see my chrome browser, right? Can you access...

  * = running now
```

| Input | Action |
| --- | --- |
| `3` | resume session 3 in a new tab of the `claude` window |
| `3h` | resume session 3 right here in this console (use this over SSH) |
| `n` | start a new session: pick a recent folder by number or type a path |
| `nh` | same, run here |
| `r` | refresh |
| `q` | quit |

Sessions marked `*` are running now. Resuming one asks for confirmation first, because a second copy would write to the same history.

Each line shows the conversation's title: the name you gave it with `/rename`, otherwise the one Claude generated, otherwise your first prompt. Throwaway sub-sessions started by other tools (SDK sessions) are hidden.

**Always the same conversation.** Resuming uses the session ID, never a fork, so you continue the original history. Claude can only find a conversation when started from the folder it was created in, so before launching, the dispatcher (and the reboot resume) check that the transcript exists and pick a folder that matches where it is stored. If none does, for example because the folder was deleted or renamed, you get a clear message (or a line in `resume.log`) instead of a tab that says "no conversation found".

## Remote Control

Every session this tool launches, whether resumed after a reboot or started or resumed from the dispatcher, runs with [Remote Control](https://code.claude.com/docs/en/remote-control) enabled, so you can reach it from claude.ai/code or the Claude mobile app. Each session is named after its conversation title (or its folder, when it has no title yet), which makes it easy to spot in the session list.

Resumed sessions run `claude --resume <id> --remote-control "<title>"`, and new ones run `claude --remote-control "<folder>"`.

To change this, create `%USERPROFILE%\.claude\session-registry\config.json`:

```json
{ "claudeArgs": "--remote-control" }
```

`claudeArgs` replaces the default arguments added to every `claude` command. `{name}` is replaced by the conversation title or folder name, and an empty string (`""`) turns Remote Control off. The file survives upgrades, because `install.ps1` never touches it. Sessions you start by hand with a plain `claude` are not affected.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall          # remove hooks + tasks
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall -Purge   # also delete installed files
```

## Limitations

- An interrupted turn is not continued. You get the conversation back, not the running process. Dev servers, background jobs and shells need restarting.
- Terminal scrollback is not restored; the transcript is.
- Tabs open on the interactive desktop. Over RDP they are waiting for you. Over SSH there is no desktop to show them, so use the `h` options to run in your own console.
- Hooks only register sessions started after install.

## More

- [How it works](docs/how-it-works.md): the registry, the heartbeat, and how a reboot is told apart from a closed window
- [Troubleshooting](docs/troubleshooting.md): logs, dry runs, common problems

## License

MIT
