<#
.SYNOPSIS
    Lists every enabled (active) Active Directory user for HR payroll reconciliation.
.DESCRIPTION
    Queries Active Directory for all enabled user accounts and writes an HR-friendly report to both
    CSV and HTML. The report contains plain-language headings: Full Name, AD Network Username,
    Email, and Account Created.

    Disabled accounts are excluded. The report is read-only against Active Directory.
    Dates are date-only and use the toolkit-wide `dd MMM yyyy` format. Output is always written
    beneath ADToolkit\Reports\ActiveUserReport regardless of the current working directory,
    unless an explicit output path is supplied.
.PARAMETER SearchBase
    Optional Distinguished Name of an OU to limit the search.
.PARAMETER OutputCsvPath
    Optional CSV output path. By default the report is written beneath ADToolkit\Reports.
.PARAMETER OutputHtmlPath
    Optional HTML output path. By default the report is written beneath ADToolkit\Reports.
.NOTES
    Public function: Invoke-ActiveUserReport
    Part of: Rance Timber AD Toolkit
    Read-only against Active Directory.
#>
function Invoke-ActiveUserReport {
    [CmdletBinding()]
    param(
        [string]$SearchBase,
        [string]$OutputCsvPath,
        [string]$OutputHtmlPath
    )

    $Config = $ADToolkitConfig.ActiveUserReport
    $DateFormat = $ADToolkitConfig.ReportDateFormat
    $OutputDirectory = Join-Path -Path $ADToolkitConfig.ReportsDirectory -ChildPath $Config.OutputDirectoryName

    if (-not (Test-ADModuleAvailable)) {
        Write-Host 'The ActiveDirectory PowerShell module is not installed. Install RSAT-AD-PowerShell and try again.' -ForegroundColor $Theme.Error
        return
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }

    $AdParams = @{
        Filter      = 'Enabled -eq $true'
        Properties  = @('DisplayName', 'EmailAddress', 'whenCreated')
        ErrorAction = 'Stop'
    }
    if ($SearchBase) { $AdParams.SearchBase = $SearchBase }

    Write-Host 'Querying Active Directory for enabled users...' -ForegroundColor $Theme.Muted
    try {
        $ActiveUsers = @(Get-ADUser @AdParams)
    }
    catch {
        Write-Host "Failed to query Active Directory: $_" -ForegroundColor $Theme.Error
        return
    }

    $RunDate = Get-Date
    $Results = @($ActiveUsers |
        ForEach-Object {
            [PSCustomObject]@{
                'Full Name'           = if ($_.DisplayName) { $_.DisplayName } else { $_.Name }
                'AD Network Username' = $_.SamAccountName
                'Email'               = $_.EmailAddress
                'Account Created'     = if ($_.whenCreated) { $_.whenCreated.ToString($DateFormat) } else { '' }
            }
        } |
        Sort-Object -Property 'Full Name', 'AD Network Username')

    Clear-Host
    Write-Host ''
    Write-Host 'Active Domain Users' -ForegroundColor $Theme.Title
    Write-Host ('=' * 19) -ForegroundColor $Theme.Title
    Write-Host ''
    Write-Host ("{0,-13}: {1}" -f 'Report date', $RunDate.ToString($DateFormat)) -ForegroundColor $Theme.Text
    Write-Host ("{0,-13}: {1}" -f 'Active users', $Results.Count) -ForegroundColor $Theme.Text
    Write-Host ''
    if ($Results.Count -gt 0) {
        Show-BorderedTable -InputObject $Results -Columns @('Full Name', 'AD Network Username', 'Email', 'Account Created')
    }
    else {
        Write-Host 'No enabled users were found.' -ForegroundColor $Theme.Warn
    }

    $FileStamp = $RunDate.ToString('yyyyMMdd')
    if (-not $OutputCsvPath) { $OutputCsvPath = Join-Path -Path $OutputDirectory -ChildPath "$($Config.OutputFilePrefix)_$FileStamp.csv" }
    if (-not $OutputHtmlPath) { $OutputHtmlPath = Join-Path -Path $OutputDirectory -ChildPath "$($Config.OutputFilePrefix)_$FileStamp.html" }

    try {
        $Results | Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        $null = Export-ToolkitHtmlReport -CsvPath $OutputCsvPath -HtmlPath $OutputHtmlPath
    }
    catch {
        Write-Host "Failed to write report files: $_" -ForegroundColor $Theme.Error
        return
    }

    Write-Host ''
    Write-Host "CSV report exported to : $OutputCsvPath" -ForegroundColor $Theme.Success
    Write-Host "HTML report exported to: $OutputHtmlPath" -ForegroundColor $Theme.Success
}
