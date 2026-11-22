# Claude Code hook: maintains the running-session registry.
#   -Event start : SessionStart  -> register session (records claude.exe PID)
#   -Event stop  : Stop          -> refresh last_active
#   -Event end   : SessionEnd    -> unregister on a deliberate exit
param([Parameter(Mandatory)][ValidateSet('start', 'stop', 'end')][string]$Event)

$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'common.ps1')

    $raw = [Console]::In.ReadToEnd()
    $in  = $raw | ConvertFrom-Json
    $id  = [string]$in.session_id
    if ($id -notmatch '^[0-9a-fA-F-]{8,}$') { exit 0 }
    $file = Join-Path $script:Dir "$id.json"
    $now  = [DateTime]::UtcNow.ToString('o')

    function Get-ClaudePid {
        $procs = @{}
        Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name |
            ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
        $cur = $PID
        for ($i = 0; $i -lt 12 -and $procs.ContainsKey($cur); $i++) {
            if ($procs[$cur].Name -match '^claude(\.exe)?$') { return $cur }
            $cur = [int]$procs[$cur].ParentProcessId
        }
        return $null
    }

    switch ($Event) {
        'start' {
            $cpid = Get-ClaudePid
            $pstart = $null
            if ($cpid) { try { $pstart = (Get-Process -Id $cpid).StartTime.ToFileTimeUtc() } catch {} }
            # One claude process = one live session. Drop older ids owned by the same process (/clear, resume).
            if ($cpid) {
                Get-Entries | Where-Object { $_.pid -eq $cpid -and $_.session_id -ne $id } |
                    ForEach-Object { Remove-Item -LiteralPath (Join-Path $script:Dir "$($_.session_id).json") -Force -ErrorAction SilentlyContinue }
            }
            Write-Entry ([pscustomobject]@{
                session_id = $id; cwd = [string]$in.cwd; pid = $cpid; pid_start = $pstart
                started = $now; last_active = $now; ended_reason = $null
            })
        }
        'stop' {
            $e = if (Test-Path -LiteralPath $file) { Read-Entry $file } else { $null }
            if ($e) { $e.last_active = $now; Write-Entry $e }
        }
        'end' {
            $reason = [string]$in.reason
            # Deliberate exits unregister immediately. Anything else (window closed, OS shutdown) keeps the
            # entry: whether it gets resumed is decided at logon from the heartbeat, not from this event.
            if ($reason -in @('prompt_input_exit', 'clear', 'logout', 'resume')) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            } else {
                $e = if (Test-Path -LiteralPath $file) { Read-Entry $file } else { $null }
                if ($e) { $e.ended_reason = $(if ($reason) { $reason } else { 'unknown' }); Write-Entry $e }
            }
        }
    }
} catch {
    try { Add-Content -LiteralPath (Join-Path $env:USERPROFILE '.claude\session-registry\hook-errors.log') -Value "$(Get-Date -Format o) [$Event] $($_.Exception.Message)" } catch {}
}
exit 0
