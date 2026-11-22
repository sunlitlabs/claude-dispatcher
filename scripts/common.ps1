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

# ---- transcripts ---------------------------------------------------------------
# Claude Code stores each conversation as ~\.claude\projects\<folder-key>\<session-id>.jsonl, where <folder-key>
# is the working directory with every non-alphanumeric character replaced by '-'. `claude --resume <id>` only finds
# the conversation when started from a folder whose key matches. These helpers make sure we resume the SAME one.
$script:ProjectsDir = Join-Path $env:USERPROFILE '.claude\projects'

function ConvertTo-ProjectKey([string]$Cwd) { $Cwd -replace '[^A-Za-z0-9]', '-' }

function Find-Transcript([string]$SessionId, [string]$Cwd) {
    if ($SessionId -notmatch '^[0-9a-fA-F-]{8,}$') { return $null }
    if ($Cwd) {
        $p = Join-Path (Join-Path $script:ProjectsDir (ConvertTo-ProjectKey $Cwd)) "$SessionId.jsonl"
        if (Test-Path -LiteralPath $p) { return Get-Item -LiteralPath $p }
    }
    Get-ChildItem (Join-Path $script:ProjectsDir "*\$SessionId.jsonl") -ErrorAction SilentlyContinue | Select-Object -First 1
}

# The folder to start `claude --resume` in: an existing directory whose key matches the transcript's project folder.
# Candidates are $Hint plus every distinct cwd recorded near the top of the transcript. $null if none fits.
function Resolve-ResumeCwd($File, [string]$Hint) {
    $key = $File.Directory.Name
    $cands = New-Object System.Collections.Generic.List[string]
    if ($Hint) { $cands.Add($Hint) }
    foreach ($line in (Get-Content -LiteralPath $File.FullName -TotalCount 300 -ErrorAction SilentlyContinue)) {
        if ($line -notmatch '"cwd":"') { continue }
        $o = try { $line | ConvertFrom-Json } catch { continue }
        if ($o.cwd -and -not $cands.Contains([string]$o.cwd)) { $cands.Add([string]$o.cwd) }
    }
    foreach ($c in $cands) {
        if ((ConvertTo-ProjectKey $c) -ieq $key -and (Test-Path -LiteralPath $c -PathType Container)) { return $c }
    }
    $null
}

# The conversation's name: a /rename title if set, else Claude's auto-generated one. Both are re-written near the
# end of the transcript as it grows, so reading the tail is enough (and cheap even for very large files).
function Get-SessionTitle($File) {
    $fs = [IO.File]::Open($File.FullName, 'Open', 'Read', 'ReadWrite')   # live sessions keep the file open
    try {
        $n = [int][Math]::Min($fs.Length, 524288)
        [void]$fs.Seek($fs.Length - $n, 'Begin')
        $buf = New-Object byte[] $n
        $n = $fs.Read($buf, 0, $n)
        $text = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
    } finally { $fs.Dispose() }
    $custom = $null; $ai = $null
    foreach ($line in ($text -split "`n")) {
        if ($line.Contains('"type":"custom-title"')) { $o = try { $line | ConvertFrom-Json } catch { $null }; if ($o.customTitle) { $custom = [string]$o.customTitle } }
        elseif ($line.Contains('"type":"ai-title"')) { $o = try { $line | ConvertFrom-Json } catch { $null }; if ($o.aiTitle) { $ai = [string]$o.aiTitle } }
    }
    if ($custom) { $custom } else { $ai }
}
