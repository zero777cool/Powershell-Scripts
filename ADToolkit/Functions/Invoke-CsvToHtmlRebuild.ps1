<#
.SYNOPSIS
    Rebuilds a report's HTML file from its (possibly edited) CSV.
.DESCRIPTION
    Every ADToolkit report writes a CSV and builds its HTML from that CSV. If you remove rows from
    a CSV (for example, people who should not appear in the report sent to HR), run this command
    to regenerate the HTML so it contains exactly the rows that are left in the CSV.

    The HTML is written next to the CSV with the same file name and overwrites the existing HTML.
    The CSV itself is never modified. Comma- and semicolon-delimited CSVs are both supported, so
    files re-saved from Excel work.
.PARAMETER CsvPath
    Optional path to the CSV to rebuild. If omitted, the command lists the most recent CSV reports
    beneath ADToolkit\Reports and prompts for one.
.NOTES
    Public function: Invoke-CsvToHtmlRebuild
    Part of: Rance Timber AD Toolkit
    Does not connect to Active Directory or Microsoft 365.
#>
function Invoke-CsvToHtmlRebuild {
    [CmdletBinding()]
    param(
        [string]$CsvPath
    )

    $MaximumListed = 20

    if (-not $CsvPath) {
        $ReportsDirectory = $ADToolkitConfig.ReportsDirectory
        $CsvFiles = @()
        if (Test-Path -LiteralPath $ReportsDirectory) {
            $CsvFiles = @(Get-ChildItem -LiteralPath $ReportsDirectory -Filter '*.csv' -File -Recurse |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First $MaximumListed)
        }

        if ($CsvFiles.Count -eq 0) {
            Write-Host 'No CSV reports were found. Run one of the reports first.' -ForegroundColor $Theme.Warn
            return
        }

        Write-Host ''
        Write-Host 'Rebuild HTML from an edited CSV' -ForegroundColor $Theme.Title
        Write-Host ('=' * 31) -ForegroundColor $Theme.Title
        Write-Host ''
        Write-Host 'Remove rows from the CSV first, save it as CSV, then pick it here.' -ForegroundColor $Theme.Muted
        Write-Host "Most recent CSV reports (newest first, up to $MaximumListed):" -ForegroundColor $Theme.Muted
        Write-Host ''

        $RootPrefix = [System.IO.Path]::GetFullPath($ReportsDirectory).TrimEnd('\', '/')
        for ($Index = 0; $Index -lt $CsvFiles.Count; $Index++) {
            $RelativeName = $CsvFiles[$Index].FullName
            if ($RelativeName.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $RelativeName = $RelativeName.Substring($RootPrefix.Length).TrimStart('\', '/')
            }
            Write-Host ("   [{0}] " -f ($Index + 1)) -ForegroundColor $Theme.Accent -NoNewline
            Write-Host $RelativeName -ForegroundColor $Theme.Text -NoNewline
            Write-Host ("  (edited {0})" -f $CsvFiles[$Index].LastWriteTime.ToString($ADToolkitConfig.ReportDateFormat)) -ForegroundColor $Theme.Muted
        }

        Write-Host ''
        $Selection = Read-Host 'Enter a number (or press Enter to cancel)'
        if ([string]::IsNullOrWhiteSpace($Selection)) {
            Write-Host 'Cancelled.' -ForegroundColor $Theme.Muted
            return
        }

        $SelectedNumber = 0
        if (-not [int]::TryParse($Selection.Trim(), [ref]$SelectedNumber) -or $SelectedNumber -lt 1 -or $SelectedNumber -gt $CsvFiles.Count) {
            Write-Host "Invalid selection: '$Selection'" -ForegroundColor $Theme.Error
            return
        }
        $CsvPath = $CsvFiles[$SelectedNumber - 1].FullName
    }

    try {
        $HtmlPath = Export-ToolkitHtmlReport -CsvPath $CsvPath
        $RecordCount = @(Import-Csv -LiteralPath $CsvPath -Delimiter (Get-ToolkitCsvDelimiter -Path $CsvPath)).Count
    }
    catch {
        Write-Host "Failed to rebuild the HTML report: $_" -ForegroundColor $Theme.Error
        return
    }

    Write-Host ''
    Write-Host "Records in CSV   : $RecordCount" -ForegroundColor $Theme.Text
    Write-Host "HTML rebuilt     : $HtmlPath" -ForegroundColor $Theme.Success
}
