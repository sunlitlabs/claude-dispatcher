# Run every minute by a scheduled task. Refreshes last_active for sessions whose claude.exe is still alive,
# and records a global heartbeat (~ the moment the machine went down, once it stops ticking).
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')

# Stay inert until resume.ps1 has handled this boot, otherwise we'd overwrite the evidence it needs.
$boot   = Get-BootTime
$marker = Join-Path $script:Root 'last-resume-boot.txt'
$handled = (Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $boot.ToString('o'))
if (-not $handled -and ((Get-Date) - $boot).TotalMinutes -lt 15) { exit 0 }

$now = [DateTime]::UtcNow.ToString('o')
foreach ($e in Get-Entries) {
    if (Test-EntryAlive $e) {
        $file = Join-Path $script:Dir "$($e.session_id).json"
        if (Test-Path -LiteralPath $file) { $e.last_active = $now; Write-Entry $e }
    } elseif (([DateTime]::UtcNow - [DateTime]::Parse($e.last_active).ToUniversalTime()).TotalDays -gt 7) {
        Remove-Item -LiteralPath (Join-Path $script:Dir "$($e.session_id).json") -Force
    }
}
Set-Content -LiteralPath (Join-Path $script:Root 'heartbeat.txt') -Value $now
