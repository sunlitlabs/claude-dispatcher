<#
.SYNOPSIS
  Installs claude-dispatcher: copies the scripts, adds the Claude Code hooks, registers the scheduled tasks.
.DESCRIPTION
  Safe to re-run (idempotent); re-running after a `git pull` upgrades the installed copy.
  Never touches the live session registry (sessions\) or logs when upgrading.
.PARAMETER Uninstall
  Remove the hooks from settings.json and unregister the scheduled tasks. Installed files are left in place.
.PARAMETER Purge
  With -Uninstall, also delete the installed files (including the session registry and logs).
#>
[CmdletBinding()]
param([switch]$Uninstall, [switch]$Purge)
$ErrorActionPreference = 'Stop'

$repo         = $PSScriptRoot
$target       = Join-Path $env:USERPROFILE '.claude\session-registry'
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
$marker       = 'session-registry\hook.ps1'   # identifies our hook entries in settings.json

# ---- 1. copy files --------------------------------------------------------------
$binDir = $null
if (-not $Uninstall) {
    New-Item -ItemType Directory -Force $target | Out-Null
    Copy-Item (Join-Path $repo 'scripts\*.ps1') $target -Force

    # cdispatch.cmd goes in the first of these that is already on PATH
    $onPath = $env:Path -split ';' | Where-Object { $_ }
    $binDir = @((Join-Path $env:USERPROFILE '.local\bin'), (Join-Path $env:USERPROFILE 'bin')) |
        Where-Object { $_ -in $onPath -and (Test-Path $_) } | Select-Object -First 1
    if (-not $binDir) { $binDir = Join-Path $target 'bin'; New-Item -ItemType Directory -Force $binDir | Out-Null; $binNote = $true }
    Copy-Item (Join-Path $repo 'bin\cdispatch.cmd') $binDir -Force
}

# ---- 2. hooks in settings.json --------------------------------------------------
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak-claude-dispatcher" -Force
    $s = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force (Split-Path $settingsPath) | Out-Null
    $s = [pscustomobject]@{}
}
if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }

$map = @{ SessionStart = 'start'; Stop = 'stop'; SessionEnd = 'end' }
foreach ($ev in $map.Keys) {
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target\hook.ps1`" -Event $($map[$ev])"
    $existing = @(); if ($s.hooks.PSObject.Properties[$ev]) { $existing = @($s.hooks.$ev) }
    # drop our previous entry, keep everyone else's hooks
    $kept = @($existing | Where-Object { -not (($_.hooks | ForEach-Object { $_.command }) -match [regex]::Escape($marker)) })
    if (-not $Uninstall) { $kept += [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $cmd }) } }
    if ($kept.Count -gt 0) {
        if ($s.hooks.PSObject.Properties[$ev]) { $s.hooks.$ev = $kept } else { $s.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue $kept }
    } elseif ($s.hooks.PSObject.Properties[$ev]) { $s.hooks.PSObject.Properties.Remove($ev) }
}
if (-not @($s.hooks.PSObject.Properties).Count) { $s.PSObject.Properties.Remove('hooks') }
$s | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8

# ---- 3. scheduled tasks ---------------------------------------------------------
foreach ($n in 'ClaudeSessionResume', 'ClaudeSessionHeartbeat') { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue }

if ($Uninstall) {
    if ($Purge) {
        Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem (Join-Path $env:USERPROFILE '.local\bin\cdispatch.cmd'), (Join-Path $env:USERPROFILE 'bin\cdispatch.cmd') -ErrorAction SilentlyContinue | Remove-Item -Force
        'Uninstalled: hooks and tasks removed, files purged.'
    } else { 'Uninstalled: hooks and tasks removed. Files left in ' + $target + ' (use -Purge to delete).' }
    return
}

$user   = "$env:USERDOMAIN\$env:USERNAME"
$princ  = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$common = @{ AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true; StartWhenAvailable = $true }

$resumeAct = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target\resume.ps1`" -Delay 15"
Register-ScheduledTask -TaskName 'ClaudeSessionResume' -Principal $princ -Action $resumeAct `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) `
    -Settings (New-ScheduledTaskSettingsSet @common -ExecutionTimeLimit (New-TimeSpan -Minutes 5)) | Out-Null

$hbAct = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target\heartbeat.ps1`""
Register-ScheduledTask -TaskName 'ClaudeSessionHeartbeat' -Principal $princ -Action $hbAct `
    -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)) `
    -Settings (New-ScheduledTaskSettingsSet @common -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)) | Out-Null

"Installed to $target"
"  hooks:  SessionStart, Stop, SessionEnd  (settings backup: settings.json.bak-claude-dispatcher)"
"  tasks:  ClaudeSessionResume (at logon), ClaudeSessionHeartbeat (every minute)"
"  cmd:    $binDir\cdispatch.cmd"
if ($binNote) { "  note:   $binDir is not on your PATH; add it to run 'cdispatch' from anywhere." }
"Sessions already running are not tracked; restart them once so the hooks register them."
