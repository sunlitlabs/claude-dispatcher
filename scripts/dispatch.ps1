# Claude dispatcher: start new sessions or resume closed ones. Opens each as a tab in the "claude" terminal window.
#   <number>      resume that session in a new tab        <number>h  resume it right here in this console
#   n             new session (pick a recent folder or type a path)     nh  same, but run here
#   r refresh     q quit
param([int]$Count = 30)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'launch.ps1')

function Get-TranscriptInfo($file) {
    $cwd = $null; $prompt = $null; $sdk = $false
    foreach ($line in (Get-Content -LiteralPath $file.FullName -TotalCount 80 -ErrorAction SilentlyContinue)) {
        $o = try { $line | ConvertFrom-Json } catch { continue }
        if ($o.entrypoint -eq 'sdk-cli') { $sdk = $true }   # a sub-session spawned by a tool, not a conversation you'd resume
        if (-not $cwd -and $o.cwd) { $cwd = [string]$o.cwd }
        if (-not $prompt -and $o.type -eq 'user' -and $o.message.role -eq 'user') {
            $c = $o.message.content
            if ($c -isnot [string]) { $c = ($c | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text }
            if ($c -and $c -notmatch '^\s*<') { $prompt = (($c -replace '\s+', ' ').Trim()) }
        }
        if ($cwd -and $prompt) { break }
    }
    [pscustomobject]@{ Id = $file.BaseName; Cwd = $cwd; Prompt = $prompt; Title = (Get-SessionTitle $file); Sdk = $sdk; File = $file; When = $file.LastWriteTime }
}

function Get-Age([datetime]$t) {
    $s = (Get-Date) - $t
    if ($s.TotalMinutes -lt 60) { return '{0}m' -f [int]$s.TotalMinutes }
    if ($s.TotalHours -lt 48)   { return '{0}h' -f [int]$s.TotalHours }
    '{0}d' -f [int]$s.TotalDays
}

function Show-Menu {
    $running = @{}
    foreach ($e in Get-Entries) { if (Test-EntryAlive $e) { $running[$e.session_id] = $true } }
    $files = Get-ChildItem (Join-Path $env:USERPROFILE '.claude\projects\*\*.jsonl') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First $Count
    $list = @($files | ForEach-Object { Get-TranscriptInfo $_ } | Where-Object { $_.Cwd -and -not $_.Sdk })
    Clear-Host
    Write-Host 'Claude dispatcher' -ForegroundColor Cyan
    Write-Host '  [number] resume in tab   [number]h resume here   n new   r refresh   q quit' -ForegroundColor DarkGray
    Write-Host ''
    for ($i = 0; $i -lt $list.Count; $i++) {
        $it = $list[$i]; $on = $running.ContainsKey($it.Id)
        $p = if ($it.Title) { $it.Title } elseif ($it.Prompt) { $it.Prompt } else { '(no title)' }
        if ($p.Length -gt 60) { $p = $p.Substring(0, 57) + '...' }
        $mark = if ($on) { '*' } else { ' ' }
        $line = '{0,3}{1} {2,4}  {3,-22} {4}' -f ($i + 1), $mark, (Get-Age $it.When), (Split-Path $it.Cwd -Leaf), $p
        Write-Host $line -ForegroundColor $(if ($on) { 'Green' } else { 'Gray' })
    }
    Write-Host "`n  * = running now" -ForegroundColor DarkGray
    return $list
}

function Start-Spec($spec, [bool]$Here) {
    if ($Here) {
        Push-Location -LiteralPath $spec.Cwd
        try { Invoke-Expression $spec.Command } finally { Pop-Location }
    } else {
        Open-ClaudeTabs @($spec)
        Write-Host "Opened '$($spec.Title)' in a new tab." -ForegroundColor Green
        Start-Sleep -Milliseconds 900
    }
}

$list = Show-Menu
while ($true) {
    $in = (Read-Host "`n>").Trim().ToLower()
    if ($in -eq 'q') { break }
    if ($in -eq 'r' -or $in -eq '') { $list = Show-Menu; continue }

    $here = $in.EndsWith('h'); if ($here) { $in = $in.Substring(0, $in.Length - 1) }

    if ($in -eq 'n') {
        $dirs = @($list | ForEach-Object { $_.Cwd } | Select-Object -Unique -First 10)
        for ($i = 0; $i -lt $dirs.Count; $i++) { Write-Host ('  {0,2}) {1}' -f ($i + 1), $dirs[$i]) }
        $d = (Read-Host 'Folder (number from above, or a path)').Trim().Trim('"')
        if ($d -match '^\d+$' -and [int]$d -ge 1 -and [int]$d -le $dirs.Count) { $d = $dirs[[int]$d - 1] }
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { Write-Host "Not a folder: $d" -ForegroundColor Red; continue }
        Start-Spec (New-FreshSpec (Resolve-Path -LiteralPath $d).Path) $here
        $list = Show-Menu; continue
    }

    if ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $list.Count) {
        $it = $list[[int]$in - 1]
        # Resume the SAME conversation: start in the folder whose project key matches the transcript's location,
        # otherwise `claude --resume` would not find it (or would be looking at a different project's history).
        $cwd = Resolve-ResumeCwd $it.File $it.Cwd
        if (-not $cwd) {
            Write-Host "Can't resume: no existing folder matches where this conversation is stored ($($it.File.Directory.Name))." -ForegroundColor Red
            Write-Host "  Recreate or restore the original folder (it was '$($it.Cwd)'), then try again." -ForegroundColor DarkGray
            continue
        }
        $live = Get-Entries | Where-Object { $_.session_id -eq $it.Id -and (Test-EntryAlive $_) }
        if ($live -and (Read-Host 'That conversation is open in another window. A second copy would write to the same history. Open anyway? (y/N)') -ne 'y') { continue }
        Start-Spec (New-ResumeSpec $it.Id $cwd $it.Title) $here
        $list = Show-Menu; continue
    }
    Write-Host 'Unrecognised input.' -ForegroundColor Red
}
