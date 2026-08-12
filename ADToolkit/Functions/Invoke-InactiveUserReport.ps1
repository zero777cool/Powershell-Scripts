<#
.SYNOPSIS
    Reports on Active Directory user accounts that have not logged in within a specified number of months.

.DESCRIPTION
    Queries on-premises Active Directory for user accounts and flags any whose last logon is older
    than the configured cutoff date (or who have never logged on, excluding accounts newer than the
    cutoff). Also flags PasswordNeverExpires and membership in a configurable list of privileged AD
    groups, so higher-risk stale accounts stand out. Outputs to console, CSV, and a styled HTML report.

    By default this uses LastLogonTimestamp, which IS replicated between Domain Controllers but can lag
    up to ~9-14 days (controlled by ms-DS-Logon-Time-Sync-Interval). For month-level reporting this is
    fine in almost all cases. Use -Accurate if you need a precise value - it queries every DC directly
    for the true (non-replicated) LastLogon attribute and takes the maximum, but is slower.

    Part of the Rance Timber AD Toolkit. Assumes Functions\Common.ps1 has already been dot-sourced
    (Show-BorderedTable, $Theme, $HtmlThemeStyle, Test-ADModuleAvailable) - this happens automatically
    when launched via ADToolkit.ps1. Can also be dot-sourced and called standalone.

.PARAMETER IncludeDisabled
    Include disabled accounts in the results. By default, disabled accounts are excluded.

.PARAMETER SearchBase
    Optional Distinguished Name of an OU to limit the search to, e.g. "OU=Staff,DC=rancetimber,DC=local".

.PARAMETER Accurate
    Queries every reachable Domain Controller for the true LastLogon value instead of relying on the
    replicated LastLogonTimestamp attribute. Slower in environments with several DCs, but avoids
    replication lag entirely.

.PARAMETER OutputCsvPath
    Path to export results as CSV. If omitted, one file per day is created in the current directory
    (Claude-Inactive-ADUsers_yyyyMMdd.csv), overwritten on each run within the same day.

.PARAMETER OutputHtmlPath
    Path to export results as a styled HTML report. If omitted, one file per day is created in the
    current directory (Claude-Inactive-ADUsers_yyyyMMdd.html), overwritten on each run within the same day.

.EXAMPLE
    Invoke-InactiveUserReport

.EXAMPLE
    Invoke-InactiveUserReport -IncludeDisabled -SearchBase "OU=Staff,DC=rancetimber,DC=local"

.EXAMPLE
    Invoke-InactiveUserReport -Accurate -OutputCsvPath "C:\Reports\Inactive_Q3.csv" -OutputHtmlPath "C:\Reports\Inactive_Q3.html"

.NOTES
    Author       : Jeremy
    Date Created : 2026-08-10
    Version      : 2.1
    Part of      : Rance Timber AD Toolkit (Functions\Invoke-InactiveUserReport.ps1)

    Version History (most recent 3):
        1.5 - 2026-08-10 - Replaced Format-Table with a custom bordered table renderer so columns are
                            separated by vertical divider lines.
        2.0 - 2026-08-10 - Added PasswordNeverExpires column, privileged AD group membership check,
                            and a styled HTML report export alongside the existing CSV.
        2.1 - 2026-08-11 - Converted from a standalone script into a toolkit function
                            (Invoke-InactiveUserReport) so it can be launched from the AD Toolkit menu;
                            now reuses shared theme/table/HTML helpers from Common.ps1 instead of
                            defining its own.
#>

function Invoke-InactiveUserReport {
    [CmdletBinding()]
    param(
        [switch]$IncludeDisabled,
        [string]$SearchBase,
        [switch]$Accurate,
        [string]$OutputCsvPath,
        [string]$OutputHtmlPath
    )

    # ===== CONFIGURATION (this feature only) =====
    # Change this value to adjust the inactivity threshold (in months).
    $MonthsInactive = 6

    # AD groups considered "privileged" for the purposes of this report. Add/remove as needed.
    # Membership is checked recursively, so nested group members are picked up too.
    $PrivilegedGroupNames = @(
        'Domain Admins',
        'Enterprise Admins',
        'Schema Admins',
        'Administrators',
        'Account Operators',
        'Backup Operators',
        'Server Operators',
        'Print Operators',
        'Group Policy Creator Owners'
    )
    # ==========================

    # ----- Local helpers (kept private to this feature so they can't collide with helpers -----
    # ----- other Invoke-*.ps1 feature files might define in future).                       -----

    function Get-AccurateLastLogon {
        param($SamAccountName)
        $DomainControllers = Get-ADDomainController -Filter *
        $LastLogonValues = foreach ($DC in $DomainControllers) {
            try {
                $DcUser = Get-ADUser -Identity $SamAccountName -Server $DC.HostName -Properties LastLogon -ErrorAction Stop
                $DcUser.LastLogon
            }
            catch {
                $null
            }
        }
        $Max = ($LastLogonValues | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
        if ($Max) { [DateTime]::FromFileTime($Max) } else { $null }
    }

    # Builds a SamAccountName -> "matched privileged group names" lookup by enumerating each
    # privileged group's recursive membership ONCE, rather than querying per-user (much faster).
    function Get-PrivilegedMembershipLookup {
        param([string[]]$GroupNames)

        $Lookup = @{}
        foreach ($GroupName in $GroupNames) {
            try {
                $Members = Get-ADGroupMember -Identity $GroupName -Recursive -ErrorAction Stop |
                           Where-Object { $_.objectClass -eq 'user' }
                foreach ($Member in $Members) {
                    if (-not $Lookup.ContainsKey($Member.SamAccountName)) {
                        $Lookup[$Member.SamAccountName] = [System.Collections.Generic.List[string]]::new()
                    }
                    $Lookup[$Member.SamAccountName].Add($GroupName)
                }
            }
            catch {
                Write-Warning "Could not enumerate members of privileged group '$GroupName': $_"
            }
        }
        return $Lookup
    }

    # Renders the report as a styled, self-contained dark-theme HTML file, reusing the shared
    # $HtmlThemeStyle from Common.ps1 so it matches every other report in the toolkit.
    function ConvertTo-InactiveUserHtmlReport {
        param(
            [Parameter(Mandatory = $true)][object[]]$Results,
            [Parameter(Mandatory = $true)][datetime]$RunDate,
            [Parameter(Mandatory = $true)][datetime]$CutoffDate,
            [Parameter(Mandatory = $true)][int]$MonthsInactive
        )

        $Rows = foreach ($R in $Results) {
            $RowClass = ''
            if ($R.'Privileged Groups') { $RowClass = 'privileged' }
            elseif ($R.'Password Never Expires' -eq $true) { $RowClass = 'never-expires' }

            @"
    <tr class="$RowClass">
      <td>$($R.SamAccountName)</td>
      <td>$($R.Name)</td>
      <td>$($R.Enabled)</td>
      <td class="center">$($R.'Days Since Last Logon')</td>
      <td>$($R.'Last Logon Date')</td>
      <td>$($R.'Account Created')</td>
      <td class="center">$($R.'Password Never Expires')</td>
      <td>$($R.'Privileged Groups')</td>
    </tr>
"@
        }
        $HtmlRows = $Rows -join "`n"

        return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Active Directory Inactive User Report</title>
<style>
$HtmlThemeStyle
</style>
</head>
<body>
  <h1>Active Directory Inactive User Report</h1>
  <div class="meta">
    <p><span class="label">Today's date</span>: $($RunDate.ToString('dd\/MM\/yyyy HH:mm:ss'))</p>
    <p><span class="label">Inactivity period</span>: $MonthsInactive months</p>
    <p><span class="label">Cutoff date</span>: $($CutoffDate.ToString('dd\/MM\/yyyy HH:mm:ss'))</p>
  </div>
  <p class="found">Found $($Results.Count) inactive user(s):</p>
  <table>
    <tr>
      <th>SamAccountName</th>
      <th>Name</th>
      <th>Enabled</th>
      <th class="center">Days Since Last Logon</th>
      <th>Last Logon Date</th>
      <th>Account Created</th>
      <th class="center">Password Never Expires</th>
      <th>Privileged Groups</th>
    </tr>
$HtmlRows
  </table>
  <div class="legend">
    <span class="item"><span class="swatch" style="background:#3a1414;"></span>Member of a privileged group</span>
    <span class="item"><span class="swatch" style="background:#332b00;"></span>Password never expires</span>
  </div>
</body>
</html>
"@
    }

    # ----- Main body -----

    if (-not (Test-ADModuleAvailable)) {
        Write-Host "The ActiveDirectory PowerShell module is not installed. Install RSAT-AD-PowerShell and try again." -ForegroundColor $Theme.Error
        return
    }

    $RunDate    = Get-Date
    $CutoffDate = $RunDate.AddMonths(-$MonthsInactive)

    $Properties = @('SamAccountName', 'Name', 'Enabled', 'LastLogonTimestamp', 'whenCreated', 'PasswordNeverExpires')

    $AdParams = @{
        Filter     = '*'
        Properties = $Properties
    }
    if ($SearchBase) { $AdParams['SearchBase'] = $SearchBase }

    try {
        $AllUsers = Get-ADUser @AdParams
    }
    catch {
        Write-Host "Failed to query Active Directory: $_" -ForegroundColor $Theme.Error
        return
    }

    if (-not $IncludeDisabled) {
        $AllUsers = $AllUsers | Where-Object { $_.Enabled -eq $true }
    }

    Write-Host "Checking privileged group membership..." -ForegroundColor $Theme.Muted
    $PrivilegedLookup = Get-PrivilegedMembershipLookup -GroupNames $PrivilegedGroupNames

    $Results = foreach ($User in $AllUsers) {

        if ($Accurate) {
            $LastLogonDate = Get-AccurateLastLogon -SamAccountName $User.SamAccountName
        }
        else {
            if ($User.LastLogonTimestamp) {
                $LastLogonDate = [DateTime]::FromFileTime($User.LastLogonTimestamp)
            }
            else {
                $LastLogonDate = $null
            }
        }

        # Never logged on: only flag as stale if the account itself predates the cutoff.
        $IsStale = $false
        if ($null -eq $LastLogonDate) {
            if ($User.whenCreated -lt $CutoffDate) { $IsStale = $true }
        }
        elseif ($LastLogonDate -lt $CutoffDate) {
            $IsStale = $true
        }

        if ($IsStale) {
            # Days Since Last Logon must always be a whole integer. For accounts that have
            # never logged on, base it on the account creation date instead.
            if ($LastLogonDate) {
                $DaysSince        = (New-TimeSpan -Start $LastLogonDate -End $RunDate).Days
                $LastLogonDisplay = $LastLogonDate.ToString('dd\/MM\/yyyy')
            }
            else {
                $DaysSince        = (New-TimeSpan -Start $User.whenCreated -End $RunDate).Days
                $LastLogonDisplay = 'Never'
            }

            $PrivilegedGroupsForUser = if ($PrivilegedLookup.ContainsKey($User.SamAccountName)) {
                ($PrivilegedLookup[$User.SamAccountName] | Sort-Object -Unique) -join ', '
            }
            else {
                ''
            }

            [PSCustomObject]@{
                SamAccountName            = $User.SamAccountName
                Name                      = $User.Name
                Enabled                   = $User.Enabled
                'Days Since Last Logon'   = $DaysSince
                'Last Logon Date'         = $LastLogonDisplay
                'Account Created'         = $User.whenCreated.ToString('dd\/MM\/yyyy')
                'Password Never Expires'  = $User.PasswordNeverExpires
                'Privileged Groups'       = $PrivilegedGroupsForUser
            }
        }
    }

    $Results = $Results | Sort-Object 'Days Since Last Logon' -Descending

    # ===== CONSOLE REPORT =====
    Clear-Host
    Write-Host ""
    Write-Host "Active Directory Inactive User Report" -ForegroundColor $Theme.Title
    Write-Host ("=" * 40) -ForegroundColor $Theme.Title
    Write-Host ""
    Write-Host ("{0,-18}: {1}" -f "Today's date", $RunDate.ToString('dd\/MM\/yyyy HH:mm:ss')) -ForegroundColor $Theme.Text
    Write-Host ("{0,-18}: {1}" -f "Inactivity period", "$MonthsInactive months") -ForegroundColor $Theme.Text
    Write-Host ("{0,-18}: {1}" -f "Cutoff date", $CutoffDate.ToString('dd\/MM\/yyyy HH:mm:ss')) -ForegroundColor $Theme.Text
    Write-Host ""
    Write-Host "Found $($Results.Count) inactive user(s):" -ForegroundColor $Theme.Warn
    Write-Host ""

    Show-BorderedTable -InputObject $Results -Columns @('SamAccountName', 'Name', 'Enabled', 'Days Since Last Logon', 'Last Logon Date', 'Account Created', 'Password Never Expires', 'Privileged Groups') -CenterColumns @('Days Since Last Logon')

    # ===== CSV EXPORT =====
    if (-not $OutputCsvPath) {
        $OutputCsvPath = ".\Claude-Inactive-ADUsers_$(Get-Date -Format 'yyyyMMdd').csv"
    }
    $Results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "Results exported to: $OutputCsvPath" -ForegroundColor $Theme.Success

    # ===== HTML EXPORT =====
    if (-not $OutputHtmlPath) {
        $OutputHtmlPath = ".\Claude-Inactive-ADUsers_$(Get-Date -Format 'yyyyMMdd').html"
    }
    $HtmlReport = ConvertTo-InactiveUserHtmlReport -Results $Results -RunDate $RunDate -CutoffDate $CutoffDate -MonthsInactive $MonthsInactive
    $HtmlReport | Out-File -FilePath $OutputHtmlPath -Encoding UTF8
    Write-Host "HTML report exported to: $OutputHtmlPath" -ForegroundColor $Theme.Success
}
