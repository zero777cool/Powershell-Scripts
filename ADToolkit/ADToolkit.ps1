<#
.SYNOPSIS
    Rance Timber AD Toolkit - menu-driven launcher for Active Directory reporting scripts.

.DESCRIPTION
    Loads shared configuration/helpers and feature commands, then presents a menu for running
    read-only Active Directory reports. Each feature lives in its own Functions\Invoke-*.ps1 file.

    New features should expose exactly one public Invoke-* function per file and keep private
    helper functions inside that feature file.

.NOTES
    Author       : Jeremy
    Part of      : Rance Timber AD Toolkit

    Development guidance is documented in DEVELOPMENT.md. Pester is intentionally planned for
    a later iteration; the current repository uses a lightweight static validation script first.
#>

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$RequiredToolkitFiles = @(
    'Config.ps1'
    'Functions\Common.ps1'
    'Functions\Invoke-InactiveUserReport.ps1'
    'Functions\Invoke-ADPrivilegeAudit.ps1'
)

foreach ($RelativePath in $RequiredToolkitFiles) {
    $FullPath = Join-Path $ScriptRoot $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) {
        Write-Host ''
        Write-Host 'ERROR: Missing required file:' -ForegroundColor Red
        Write-Host "  $FullPath" -ForegroundColor Red
        Write-Host ''
        Write-Host 'Make sure the whole ADToolkit folder was copied, including the Functions subfolder.' -ForegroundColor Red
        exit 1
    }
    . $FullPath
}

if (-not (Test-ADModuleAvailable)) {
    Write-Host 'The ActiveDirectory PowerShell module is not installed. Install RSAT-AD-PowerShell and try again.' -ForegroundColor $Theme.Error
    exit 1
}

$MenuItems = @(
    [PSCustomObject]@{
        Key         = '1'
        Title       = 'Inactive User Report'
        Description = 'Find users who have not logged on within the configured period'
        Action      = { Invoke-InactiveUserReport }
    }
    [PSCustomObject]@{
        Key         = '2'
        Title       = 'AD Privilege Audit'
        Description = 'Audit privileged AD groups and local Administrators across domain computers'
        Action      = { Invoke-ADPrivilegeAudit }
    }
)

function Show-MainMenu {
    Clear-Host
    Write-Host ''
    Show-Banner -Text 'RANCE TIMBER - AD TOOLKIT' -Color $Theme.Title
    Write-Host ''
    foreach ($Item in $MenuItems) {
        Write-Host ("   [{0}] " -f $Item.Key) -ForegroundColor $Theme.Accent -NoNewline
        Write-Host $Item.Title -ForegroundColor $Theme.Text
        Write-Host ("        {0}" -f $Item.Description) -ForegroundColor $Theme.Muted
    }
    Write-Host ''
    Write-Host '   [Q] ' -ForegroundColor $Theme.Accent -NoNewline
    Write-Host 'Quit' -ForegroundColor $Theme.Text
    Write-Host ''
}

do {
    Show-MainMenu
    $Choice = Read-Host 'Select an option'
    if ($Choice -match '^[Qq]$') { break }

    $Selected = $MenuItems | Where-Object { $_.Key -eq $Choice }
    if ($Selected) {
        Clear-Host
        try { & $Selected.Action }
        catch { Write-Host "The selected command failed: $_" -ForegroundColor $Theme.Error }
        Wait-KeyPress
    }
    else {
        Write-Host "Invalid selection: '$Choice'" -ForegroundColor $Theme.Error
        Start-Sleep -Seconds 1
    }
} while ($true)

Write-Host ''
Write-Host 'Goodbye.' -ForegroundColor $Theme.Title
