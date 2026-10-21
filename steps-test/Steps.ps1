<#
Steps.ps1 - in-place step checklist for PowerShell scripts (Windows PowerShell 5.1 and PowerShell 7)

    .  pending    -> running (blue)    OK done (green)    X failed (red)    skipped (yellow)
    (drawn with the real symbols: middle dot, arrow, tick, cross, skip arrow)

The list is drawn once and then updated in place; it never scrolls.
Each step's own output goes to a log file, not the screen.

USAGE
    . "$PSScriptRoot\Steps.ps1"

    Start-StepList -Title 'Workstation setup' -Steps @(
        'Check prerequisites'
        'Install packages'
        'Configure Git'
    )

    Invoke-Step 1 { if (-not (Test-Path C:\Tools)) { New-Item C:\Tools -ItemType Directory } }
    Invoke-Step 2 { Invoke-NativeCommand winget install --id Git.Git -e --silent }
    Skip-Step   3 'already configured'
    Complete-StepList

RULES OF THE ROAD
  * A step fails on any error: cmdlet errors stop it immediately ($ErrorActionPreference = 'Stop'),
    and so does a non-zero exit code from the last program it ran.
  * Run external programs (git, winget, robocopy...) through Invoke-NativeCommand. It treats
    their stderr as normal output (Windows PowerShell 5.1 would otherwise call it an error)
    and fails the step on a non-zero exit code, even if it isn't the last line.
  * Variables set inside a step vanish when the step ends. Use $script:NAME = ... to keep a
    value for later steps and the rest of the script.
  * Steps can't ask for input. Collect answers (Read-Host, Get-Credential) before Start-StepList.
  * On failure: the step turns red, its last log lines are shown, and the script exits with code 1
    (use Start-StepList -KeepGoing to carry on instead).
  * If output is redirected, the host isn't a console, or the list is taller than the window,
    it prints one plain line per step change instead (or force that with -Plain).
  * The screen is cleared when the list starts (console only, never when redirected). -NoClear skips that.
  * A few emoji mark the title, summary and log lines (wrench, party popper, siren, stop sign, page).
    Set $env:STEPS_NO_ICONS = 1 to drop them, or $env:STEPS_ASCII = 1 for plain ASCII everywhere
    (for consoles whose font has no tick/arrow glyphs).
#>

$script:StepsNames = @(); $script:StepsState = @(); $script:StepsSecs = @(); $script:StepsNote = @()
$script:StepsCount = 0; $script:StepsFancy = $false; $script:StepsTop = 0; $script:StepsWidth = 80
$script:StepsLog = ''; $script:StepsTail = 15; $script:StepsKeepGoing = $false
$script:StepsTimer = $null; $script:StepsOldEncoding = $null

if ($env:STEPS_ASCII) {
    $script:StepsSym = @{ pending = '.'; running = '>'; done = '+'; failed = 'x'; skipped = '-'; more = '~' }
} else {
    $script:StepsSym = @{
        pending = [string][char]0x00B7; running = [string][char]0x2192; done = [string][char]0x2713
        failed  = [string][char]0x2717; skipped = [string][char]0x21B7; more    = [string][char]0x2026
    }
}

# A few emoji for the title, summary and log lines (the step states keep the arrow/tick symbols).
function ConvertTo-StepIcon([int]$CodePoint) { return [char]::ConvertFromUtf32($CodePoint) + ' ' }
if ($env:STEPS_ASCII -or $env:STEPS_NO_ICONS) {
    $script:StepsIcon = @{ title = ''; done = $script:StepsSym.done + ' '; fail = $script:StepsSym.failed + ' '; stop = ''; log = '' }
} else {
    $script:StepsIcon = @{
        title = ConvertTo-StepIcon 0x1F527   # wrench
        done  = ConvertTo-StepIcon 0x1F389   # party popper
        fail  = ConvertTo-StepIcon 0x1F6A8   # siren
        stop  = ConvertTo-StepIcon 0x1F6D1   # stop sign
        log   = ConvertTo-StepIcon 0x1F4C4   # page
    }
}

# -- internals ----------------------------------------------------------------

function Format-StepTime([int]$Seconds) {
    if ($Seconds -ge 3600) { return '{0}h {1:00}m' -f [math]::Floor($Seconds / 3600), [math]::Floor(($Seconds % 3600) / 60) }
    if ($Seconds -ge 60)   { return '{0}m {1:00}s' -f [math]::Floor($Seconds / 60), ($Seconds % 60) }
    return "${Seconds}s"
}

function Write-StepLine([int]$Index) {
    # Writes one step line (no newline) as coloured segments.
    $name  = $script:StepsNames[$Index]
    $state = $script:StepsState[$Index]
    $max   = [math]::Max(10, $script:StepsWidth - 22)
    if ($name.Length -gt $max) { $name = $name.Substring(0, $max - 1) + $script:StepsSym.more }
    $sym = $script:StepsSym[$state]
    switch ($state) {
        'done' {
            Write-Host $sym -ForegroundColor Green -NoNewline
            Write-Host " $name  " -NoNewline
            Write-Host (Format-StepTime $script:StepsSecs[$Index]) -ForegroundColor DarkGray -NoNewline
        }
        'running' {
            Write-Host $sym -ForegroundColor Blue -NoNewline
            Write-Host " $name" -ForegroundColor White -NoNewline
        }
        'failed' {
            Write-Host $sym -ForegroundColor Red -NoNewline
            Write-Host " $name" -NoNewline
            if ($script:StepsNote[$Index]) { Write-Host "  $($script:StepsNote[$Index])" -ForegroundColor Red -NoNewline }
        }
        'skipped' {
            $note = if ($script:StepsNote[$Index]) { "  $($script:StepsNote[$Index])" } else { '' }
            Write-Host "$sym $name$note" -ForegroundColor Yellow -NoNewline
        }
        default { Write-Host "$sym $name" -ForegroundColor DarkGray -NoNewline }
    }
}

function Update-StepList([int]$Index) {
    if (-not $script:StepsFancy) {
        Write-Host "[$Index/$($script:StepsCount)] " -NoNewline
        Write-StepLine $Index
        Write-Host ''
        return
    }
    $blank = ' ' * [math]::Max(1, $script:StepsWidth - 1)
    for ($i = 1; $i -le $script:StepsCount; $i++) {
        $row = $script:StepsTop + $i - 1
        [Console]::SetCursorPosition(0, $row); Write-Host $blank -NoNewline
        [Console]::SetCursorPosition(0, $row); Write-StepLine $i
    }
    [Console]::SetCursorPosition(0, $script:StepsTop + $script:StepsCount)
}

function Set-StepCursor([bool]$Visible) {
    if ($script:StepsFancy) { try { [Console]::CursorVisible = $Visible } catch { } }
}

# -- public API ---------------------------------------------------------------

function Start-StepList {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Steps,
        [string]$LogPath,
        [int]$Tail = 15,
        [switch]$KeepGoing,
        [switch]$Plain,
        [switch]$NoClear
    )
    $script:StepsNames = @('') + $Steps
    $script:StepsCount = $Steps.Count
    $script:StepsState = @('') + (@('pending') * $Steps.Count)
    $script:StepsSecs  = @(0) * ($Steps.Count + 1)
    $script:StepsNote  = @('') * ($Steps.Count + 1)
    $script:StepsTail  = $Tail
    $script:StepsKeepGoing = [bool]$KeepGoing

    if (-not $LogPath) {
        $base = if ($MyInvocation.PSCommandPath) { [IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath) } else { 'steps' }
        $LogPath = Join-Path ([IO.Path]::GetTempPath()) ("{0}-{1:yyyyMMdd-HHmmss}.log" -f $base, (Get-Date))
    }
    $script:StepsLog = $LogPath
    Set-Content -Path $LogPath -Value "$Title  ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))" -Encoding UTF8

    # Fancy (in-place) mode only on a real, tall-enough console.
    $script:StepsFancy = $false
    if (-not $Plain -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected) {
        try {
            $script:StepsWidth = [Console]::WindowWidth
            if ($Steps.Count + 4 -le [Console]::WindowHeight) { $script:StepsFancy = $true }
        } catch { }
    }
    if (-not $env:STEPS_ASCII -and -not [Console]::IsOutputRedirected) {
        try { $script:StepsOldEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    }

    $script:StepsTimer = [Diagnostics.Stopwatch]::StartNew()
    if (-not $NoClear -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected) { Clear-Host }
    Write-Host "$($script:StepsIcon.title)$Title" -ForegroundColor White
    if ($script:StepsFancy) {
        for ($i = 0; $i -lt $Steps.Count; $i++) { Write-Host '' }   # reserve the rows (scrolls if needed)
        $script:StepsTop = [Console]::CursorTop - $Steps.Count
        Set-StepCursor $false
        Update-StepList 1
    } else {
        Write-Host "Steps: $($Steps.Count) - $($script:StepsIcon.log)log: $LogPath"
    }
}

function Invoke-NativeCommand {
    # Run an external program inside a step: stderr is treated as output, non-zero exit fails the step.
    param(
        [Parameter(Mandatory, Position = 0)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments)][string[]]$ArgumentList
    )
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try { & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" } }
    finally { $ErrorActionPreference = $eap }
    if ($LASTEXITCODE -ne 0) { throw "$FilePath exited with code $LASTEXITCODE" }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory, Position = 0)][int]$Number,
        [Parameter(Mandatory, Position = 1)][scriptblock]$Action
    )
    $i = $Number
    $name = $script:StepsNames[$i]
    $script:StepsState[$i] = 'running'
    Update-StepList $i
    Add-Content -Path $script:StepsLog -Encoding UTF8 -Value @(
        '', "===== [$i/$($script:StepsCount)] $name  ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))", "> $($Action.ToString().Trim())")

    $stepLog = [IO.Path]::GetTempFileName()
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $finished = $false; $failure = $null
    try {
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $true   # PowerShell 7.3+: failing programs throw
        $global:LASTEXITCODE = 0
        & $Action *>&1 | ForEach-Object { $_ | Out-String -Stream } | Add-Content -Path $stepLog -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw "last program exited with code $LASTEXITCODE" }
        $finished = $true
    } catch {
        $failure = $_
        $where = ''
        $inv = $_.InvocationInfo
        if ($inv -and $inv.ScriptName -and $inv.ScriptName -ne $PSCommandPath) {
            $where = "  (at $(Split-Path $inv.ScriptName -Leaf):$($inv.ScriptLineNumber): $($inv.Line.Trim()))"
        }
        Add-Content -Path $stepLog -Encoding UTF8 -Value ("ERROR: " + $_.Exception.Message + $where)
        $finished = $true
    } finally {
        $script:StepsSecs[$i] = [int]$watch.Elapsed.TotalSeconds
        if (Test-Path $stepLog) { Get-Content $stepLog | Add-Content -Path $script:StepsLog -Encoding UTF8 }
        if (-not $finished) {
            # Ctrl+C: the pipeline was stopped before catch could run.
            $script:StepsState[$i] = 'failed'; $script:StepsNote[$i] = 'interrupted'
            Update-StepList $i
            Set-StepCursor $true
            Write-Host "`n$($script:StepsIcon.stop)Interrupted. $($script:StepsIcon.log)Log: $($script:StepsLog)"
            Remove-Item $stepLog -ErrorAction SilentlyContinue
        }
    }

    if (-not $failure) {
        $script:StepsState[$i] = 'done'
        Update-StepList $i
        Remove-Item $stepLog -ErrorAction SilentlyContinue
        return
    }

    $script:StepsState[$i] = 'failed'
    $msg = ($failure.Exception.Message -split "`n")[0].Trim()
    if ($msg.Length -gt 40) { $msg = $msg.Substring(0, 39) + $script:StepsSym.more }
    $script:StepsNote[$i] = $msg
    Update-StepList $i
    Set-StepCursor $true
    Write-Host ''
    Write-Host "$($script:StepsIcon.fail)Step $i failed: $name. Its last output:" -ForegroundColor Red
    Get-Content $stepLog -Tail $script:StepsTail | ForEach-Object { Write-Host "  $_" }
    Write-Host "$($script:StepsIcon.log)Full log: $($script:StepsLog)"
    Remove-Item $stepLog -ErrorAction SilentlyContinue

    if ($script:StepsKeepGoing) {
        if ($script:StepsFancy) {
            # Redraw the list below the error so later steps update in the right place.
            Write-Host ''
            for ($n = 0; $n -lt $script:StepsCount; $n++) { Write-Host '' }
            $script:StepsTop = [Console]::CursorTop - $script:StepsCount
            Set-StepCursor $false
            Update-StepList $i
        }
        return
    }
    if ($script:StepsOldEncoding) { try { [Console]::OutputEncoding = $script:StepsOldEncoding } catch { } }
    exit 1
}

function Skip-Step {
    param([Parameter(Mandatory, Position = 0)][int]$Number, [Parameter(Position = 1)][string]$Reason = '')
    $script:StepsState[$Number] = 'skipped'; $script:StepsNote[$Number] = $Reason
    Add-Content -Path $script:StepsLog -Encoding UTF8 -Value @('', "===== [$Number/$($script:StepsCount)] $($script:StepsNames[$Number])  skipped $Reason")
    Update-StepList $Number
}

function Complete-StepList {
    # Prints the summary line. Returns $true if no step failed.
    Set-StepCursor $true
    $failed = @($script:StepsState | Where-Object { $_ -eq 'failed' }).Count
    $notRun = @($script:StepsState | Where-Object { $_ -eq 'pending' }).Count
    $total  = Format-StepTime ([int]$script:StepsTimer.Elapsed.TotalSeconds)
    Write-Host ''
    if ($failed) {
        Write-Host "$($script:StepsIcon.fail)$failed of $($script:StepsCount) steps failed" -ForegroundColor Red -NoNewline
        Write-Host " in $total"
        Write-Host "$($script:StepsIcon.log)Log: $($script:StepsLog)"
    } else {
        $extra = if ($notRun) { " ($notRun not run)" } else { '' }
        Write-Host "$($script:StepsIcon.done)Done" -ForegroundColor Green -NoNewline
        Write-Host " - $($script:StepsCount) step(s) in $total$extra"
        Write-Host "$($script:StepsIcon.log)Log: $($script:StepsLog)"
    }
    if ($script:StepsOldEncoding) { try { [Console]::OutputEncoding = $script:StepsOldEncoding } catch { } }
    return (-not $failed)
}
