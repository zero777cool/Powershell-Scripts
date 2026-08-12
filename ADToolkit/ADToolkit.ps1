<#
.SYNOPSIS
    Rance Timber AD Toolkit - menu-driven launcher for Active Directory reporting scripts.

.DESCRIPTION
    Shows a numbered menu of available AD commands and runs whichever one you pick. Built to
    grow: each command lives in its own file under .\Functions, and adding a new one is a
    two-step process - see "ADDING A NEW COMMAND" below.

.EXAMPLE
    .\ADToolkit.ps1
    Launches the menu.

.NOTES
    Author       : Jeremy
    Date Created : 2026-08-11
    Version      : 1.3

    ===== ADDING A NEW COMMAND =====
    1. Create a new file in .\Functions, e.g. Functions\Invoke-PasswordExpiryReport.ps1,
       following the same pattern as Invoke-InactiveUserReport.ps1 (one public function per
       file, matching the filename, with any private helpers nested inside it).
    2. Add its relative path to the $RequiredToolkitFiles array below, and add one entry to
       $MenuItems pointing at its function. That's it - no other changes needed.

    Version History (most recent 3):
        1.0 - 2026-08-11 - Initial menu launcher. Restructured from a single standalone script
                            (Get-InactiveADUsers.ps1) into this project so future AD checks
                            (password expiry, session/logon status, etc.) can be added as
                            separate commands without touching existing code.
        1.1 - 2026-08-11 - Removed all non-ASCII characters (em-dash, Unicode box-drawing) after
                            they got corrupted when read under a non-UTF-8 codepage.
        1.3 - 2026-08-12 - Refactored AD Privilege Audit into the standard Invoke-* function architecture.
        1.2 - 2026-08-11 - Fixed a scoping bug: file loading was wrapped in a function, so
                            dot-sourced content (Theme, Show-Banner, etc.) was being discarded
                            when that function returned instead of reaching script scope. Now
                            dot-sources directly at the top level via a plain loop.
#>

# Resolve the folder this script lives in, so it works regardless of the current working directory.
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Dot-sources each required toolkit file directly at this script's top level (NOT inside a
# function - dot-sourcing inside a function only loads things into that function's own local
# scope, where they disappear the moment it returns). Fails loudly and clearly if a file is
# missing rather than letting the rest of the script cascade into confusing null/undefined
# errors. $Theme isn't loaded yet for Common.ps1 itself, so colors are hardcoded here.
$RequiredToolkitFiles = @(
    'Functions\Common.ps1',
    'Functions\Invoke-InactiveUserReport.ps1',
    'Functions\Invoke-ADPrivilegeAudit.ps1'
    # Add new "Functions\Invoke-*.ps1" paths here as new commands are built.
)

foreach ($RelativePath in $RequiredToolkitFiles) {
    $FullPath = Join-Path $ScriptRoot $RelativePath
    if (-not (Test-Path $FullPath)) {
        Write-Host ""
        Write-Host "ERROR: Missing required file:" -ForegroundColor Red
        Write-Host "  $FullPath" -ForegroundColor Red
        Write-Host ""
        Write-Host "Make sure the WHOLE ADToolkit folder was extracted from the zip - including" -ForegroundColor Red
        Write-Host "the Functions subfolder - not just ADToolkit.ps1 on its own. Also check your" -ForegroundColor Red
        Write-Host "antivirus/EDR quarantine in case the .ps1 files under Functions were flagged." -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    . $FullPath
}

if (-not (Test-ADModuleAvailable)) {
    Write-Host "The ActiveDirectory PowerShell module is not installed. Install RSAT-AD-PowerShell and try again." -ForegroundColor $Theme.Error
    exit 1
}

# ===== MENU REGISTRY =====
# Add one entry here per command. Key = what the user types, Action = scriptblock to run.
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
    Write-Host ""
    Show-Banner -Text 'RANCE TIMBER - AD TOOLKIT' -Color $Theme.Title
    Write-Host ""

    foreach ($Item in $MenuItems) {
        Write-Host ("   [{0}] " -f $Item.Key) -ForegroundColor $Theme.Accent -NoNewline
        Write-Host $Item.Title -ForegroundColor $Theme.Text
        Write-Host ("        {0}" -f $Item.Description) -ForegroundColor $Theme.Muted
    }

    Write-Host ""
    Write-Host "   [Q] " -ForegroundColor $Theme.Accent -NoNewline
    Write-Host "Quit" -ForegroundColor $Theme.Text
    Write-Host ""
}

do {
    Show-MainMenu
    $Choice = Read-Host "Select an option"

    if ($Choice -match '^[Qq]$') { break }

    $Selected = $MenuItems | Where-Object { $_.Key -eq $Choice }

    if ($Selected) {
        Clear-Host
        try {
            & $Selected.Action
        }
        catch {
            Write-Host "The selected command failed: $_" -ForegroundColor $Theme.Error
        }
        Wait-KeyPress
    }
    else {
        Write-Host "Invalid selection: '$Choice'" -ForegroundColor $Theme.Error
        Start-Sleep -Seconds 1
    }
} while ($true)

Write-Host ""
Write-Host "Goodbye." -ForegroundColor $Theme.Title
