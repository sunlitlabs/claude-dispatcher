# Opens Claude sessions as tabs in one named Windows Terminal window ("claude"). Dot-source after common.ps1.

function ConvertTo-WtArg([string]$s) { '"' + ($s -replace '"', '\"') + '"' }

# $Specs: objects with Title, Cwd, Command (what to run inside the tab). Adds a Dispatcher tab first if -WithDispatcher.
function Open-ClaudeTabs($Specs, [switch]$WithDispatcher) {
    $parts = @()
    if ($WithDispatcher) {
        $d = Join-Path $PSScriptRoot 'dispatch.ps1'
        $parts += "new-tab --title Dispatcher -d $(ConvertTo-WtArg $env:USERPROFILE) powershell -NoExit -ExecutionPolicy Bypass -File $(ConvertTo-WtArg $d)"
    }
    foreach ($s in $Specs) {
        $parts += "new-tab --title $(ConvertTo-WtArg $s.Title) -d $(ConvertTo-WtArg $s.Cwd) powershell -NoExit -Command $(ConvertTo-WtArg $s.Command)"
    }
    if (-not $parts) { return }
    Start-Process wt.exe -ArgumentList ('-w claude ' + ($parts -join ' ; '))
}

# Extra arguments added to every claude command we launch. Default: Remote Control, named after the folder.
# Override with {"claudeArgs": "..."} in config.json next to these scripts ("{name}" = folder name; "" = none).
function Get-ClaudeArgs([string]$Cwd) {
    $extra = '--remote-control "{name}"'
    $cfg = Join-Path $script:Root 'config.json'
    if (Test-Path -LiteralPath $cfg) {
        try { $c = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json; if ($null -ne $c.claudeArgs) { $extra = [string]$c.claudeArgs } } catch {}
    }
    $name = (Split-Path $Cwd -Leaf) -replace '["`$]', ''
    ($extra -replace '\{name\}', $name).Trim()
}

function New-ResumeSpec([string]$SessionId, [string]$Cwd) {
    [pscustomobject]@{ Title = (Split-Path $Cwd -Leaf); Cwd = $Cwd; Command = ("claude --resume $SessionId " + (Get-ClaudeArgs $Cwd)).Trim() }
}
function New-FreshSpec([string]$Cwd) {
    [pscustomobject]@{ Title = (Split-Path $Cwd -Leaf); Cwd = $Cwd; Command = ('claude ' + (Get-ClaudeArgs $Cwd)).Trim() }
}
