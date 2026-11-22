# Run at logon. Reopens the sessions that were alive when the machine went down.
param([int]$Delay = 0, [switch]$DryRun, [switch]$Force, [int]$MaxTabs = 12, [int]$ToleranceMinutes = 4)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'launch.ps1')

$log = Join-Path $script:Root 'resume.log'
function Log($m) { Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) $m" }

$boot   = Get-BootTime
$marker = Join-Path $script:Root 'last-resume-boot.txt'
if (-not $Force -and (Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $boot.ToString('o'))) {
    Log 'already handled this boot; nothing to do'; exit 0
}

# The global heartbeat stops ticking when the machine goes down, so it approximates the shutdown moment.
$hbFile = Join-Path $script:Root 'heartbeat.txt'
$lastHb = if (Test-Path $hbFile) { [DateTime]::Parse((Get-Content $hbFile -Raw).Trim()).ToUniversalTime() } else { $null }

$entries = @(Get-Entries)
$resume = @()
if ($lastHb) {
    $cutoff = $lastHb.AddMinutes(-$ToleranceMinutes)
    $resume = @($entries | Where-Object {
        [DateTime]::Parse($_.last_active).ToUniversalTime() -ge $cutoff -and
        -not (Test-EntryAlive $_) -and $_.cwd -and (Test-Path -LiteralPath $_.cwd)
    } | Sort-Object last_active -Descending | Select-Object -First $MaxTabs)
}
Log "boot=$($boot.ToString('o')) lastHeartbeat=$lastHb entries=$($entries.Count) resuming=$($resume.Count) dryrun=$DryRun"

if ($DryRun) {
    $resume | ForEach-Object { "{0}  {1}  {2}" -f $_.session_id, $_.last_active, $_.cwd }
    exit 0
}

# Claim this boot, then drop every old entry; resumed sessions re-register themselves via SessionStart.
Set-Content -LiteralPath $marker -Value $boot.ToString('o')
foreach ($e in $entries) { Remove-Item -LiteralPath (Join-Path $script:Dir "$($e.session_id).json") -Force -ErrorAction SilentlyContinue }

if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }
$specs = $resume | ForEach-Object { New-ResumeSpec $_.session_id $_.cwd }
Open-ClaudeTabs $specs -WithDispatcher
Log "launched dispatcher + $($resume.Count) session tab(s)"
