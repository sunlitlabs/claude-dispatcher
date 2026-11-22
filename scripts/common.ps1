# Shared helpers for the Claude session registry. Dot-source this file.
$script:Root = Join-Path $env:USERPROFILE '.claude\session-registry'
$script:Dir  = Join-Path $script:Root 'sessions'
New-Item -ItemType Directory -Force $script:Dir | Out-Null

function Read-Entry([string]$Path) {
    try { Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
}

function Write-Entry($Entry) {
    $file = Join-Path $script:Dir "$($Entry.session_id).json"
    $tmp  = "$file.$PID.tmp"
    $Entry | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $file -Force
}

function Get-Entries {
    Get-ChildItem -LiteralPath $script:Dir -Filter '*.json' -ErrorAction SilentlyContinue |
        ForEach-Object { Read-Entry $_.FullName } | Where-Object { $_ -and $_.session_id }
}

# True when the claude.exe process recorded for this entry is still the same live process.
function Test-EntryAlive($Entry) {
    if (-not $Entry.pid) { return $false }
    $p = Get-Process -Id $Entry.pid -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    try { return ($p.StartTime.ToFileTimeUtc() -eq [int64]$Entry.pid_start) } catch { return $false }
}

function Get-BootTime { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
