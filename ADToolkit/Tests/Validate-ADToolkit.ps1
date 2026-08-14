<#
.SYNOPSIS
    Performs lightweight static validation of the ADToolkit.

.DESCRIPTION
    Validates expected files, Invoke-* naming, duplicate public functions, and PowerShell parser
    errors. This deliberately does not connect to Active Directory or execute report commands.

    Pester is planned for a later iteration for behavioural tests.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$RequiredFiles = @(
    'ADToolkit.ps1'
    'Config.ps1'
    'README.md'
    'DEVELOPMENT.md'
    'Functions\Common.ps1'
    'Functions\Invoke-InactiveUserReport.ps1'
    'Functions\Invoke-ADPrivilegeAudit.ps1'
    'Functions\Invoke-AllUserLogonReport.ps1'
)

$Failures = [System.Collections.Generic.List[string]]::new()

foreach ($RelativePath in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $ToolkitRoot $RelativePath) -PathType Leaf)) {
        $Failures.Add("Missing required file: $RelativePath")
    }
}

$FunctionFiles = Get-ChildItem -LiteralPath (Join-Path $ToolkitRoot 'Functions') -Filter 'Invoke-*.ps1' -File
$PublicFunctions = @()

foreach ($File in $FunctionFiles) {
    if ($File.BaseName -notmatch '^Invoke-[A-Za-z0-9]+(?:[A-Za-z0-9-]*)$') {
        $Failures.Add("Invalid feature filename: $($File.Name)")
    }

    $ExpectedFunction = $File.BaseName
    $Matches = Select-String -LiteralPath $File.FullName -Pattern "(?m)^\s*function\s+($ExpectedFunction)\s*\{" | ForEach-Object { $_.Matches.Value }
    if (-not $Matches) {
        $Failures.Add("Expected public function '$ExpectedFunction' was not found in $($File.Name)")
    }
    else {
        $PublicFunctions += $ExpectedFunction
    }

    $ParserErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$ParserErrors)
    foreach ($ParserError in @($ParserErrors)) {
        $Failures.Add("Parser error in $($File.Name): $($ParserError.Message)")
    }
}

$DuplicateFunctions = $PublicFunctions | Group-Object | Where-Object Count -gt 1
foreach ($Duplicate in $DuplicateFunctions) {
    $Failures.Add("Duplicate public function: $($Duplicate.Name)")
}

$Launcher = Join-Path $ToolkitRoot 'ADToolkit.ps1'
if (Test-Path -LiteralPath $Launcher -PathType Leaf) {
    $ParserErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Launcher, [ref]$null, [ref]$ParserErrors)
    foreach ($ParserError in @($ParserErrors)) {
        $Failures.Add("Parser error in ADToolkit.ps1: $($ParserError.Message)")
    }
}

if ($Failures.Count -gt 0) {
    Write-Host "ADToolkit validation FAILED ($($Failures.Count) issue(s))." -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'ADToolkit validation PASSED.' -ForegroundColor Green
Write-Host "Validated $($FunctionFiles.Count) feature file(s), required files, naming, duplicate public functions, and PowerShell parser syntax."
exit 0
