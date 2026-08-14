<#
.SYNOPSIS
    Reports on Active Directory user accounts that have not logged in within a specified number of months.

.DESCRIPTION
    Queries on-premises Active Directory for user accounts and flags stale accounts. It also flags
    PasswordNeverExpires and membership in configured privileged AD groups. Output is written to the
    console, CSV, and a styled HTML report.

    LastLogonTimestamp is used by default. Use -Accurate when an exact non-replicated LastLogon value
    is required; that mode queries every domain controller and is slower.

    Part of the Rance Timber AD Toolkit. Common.ps1 and Config.ps1 are loaded by ADToolkit.ps1.
    The command can also be dot-sourced and called standalone if those shared files are loaded first.

.PARAMETER IncludeDisabled
    Include disabled accounts. Disabled accounts are excluded by default.

.PARAMETER SearchBase
    Optional Distinguished Name of an OU to limit the search.

.PARAMETER Accurate
    Query every reachable Domain Controller for the true LastLogon value.

.PARAMETER OutputCsvPath
    Optional CSV output path. Defaults to ADToolkit-InactiveUsers_yyyyMMdd.csv in the current directory.

.PARAMETER OutputHtmlPath
    Optional HTML output path. Defaults to ADToolkit-InactiveUsers_yyyyMMdd.html in the current directory.

.NOTES
    Author  : Jeremy
    Part of : Rance Timber AD Toolkit
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

    $Config = $ADToolkitConfig.InactiveUserReport
    $MonthsInactive = $Config.MonthsInactive
    $PrivilegedGroupNames = $Config.PrivilegedGroupNames
    $OutputFilePrefix = $Config.OutputFilePrefix

    function Get-AccurateLastLogon {
        param($SamAccountName)
        $DomainControllers = Get-ADDomainController -Filter *
        $LastLogonValues = foreach ($DC in $DomainControllers) {
            try {
                $DcUser = Get-ADUser -Identity $SamAccountName -Server $DC.HostName -Properties LastLogon -ErrorAction Stop
                $DcUser.LastLogon
            } catch { $null }
        }
        $Max = ($LastLogonValues | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
        if ($Max) { [DateTime]::FromFileTime($Max) } else { $null }
    }

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
            } catch {
                Write-Warning "Could not enumerate members of privileged group '$GroupName': $_"
            }
        }
        return $Lookup
    }

    function ConvertTo-InactiveUserHtmlReport {
        param(
            [Parameter(Mandatory = $true)][object[]]$Results,
            [Parameter(Mandatory = $true)][datetime]$RunDate,
            [Parameter(Mandatory = $true)][datetime]$CutoffDate,
            [Parameter(Mandatory = $true)][int]$MonthsInactive
        )
        $Rows = foreach ($R in $Results) {
            $RowClass = if ($R.'Privileged Groups') { 'privileged' } elseif ($R.'Password Never Expires' -eq $true) { 'never-expires' } else { '' }
            @"
    <tr class="$RowClass">
      <td>$($R.SamAccountName)</td><td>$($R.Name)</td><td>$($R.Enabled)</td>
      <td class="center">$($R.'Days Since Last Logon')</td><td>$($R.'Last Logon Date')</td>
      <td>$($R.'Account Created')</td><td class="center">$($R.'Password Never Expires')</td>
      <td>$($R.'Privileged Groups')</td>
    </tr>
"@
        }
        $HtmlRows = $Rows -join "`n"
        return @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<title>Active Directory Inactive User Report</title>
<style>$HtmlThemeStyle</style></head>
<body>
<h1>Active Directory Inactive User Report</h1>
<div class="meta">
<p><span class="label">Today's date</span>: $($RunDate.ToString('dd\/MM\/yyyy HH:mm:ss'))</p>
<p><span class="label">Inactivity period</span>: $MonthsInactive months</p>
<p><span class="label">Cutoff date</span>: $($CutoffDate.ToString('dd\/MM\/yyyy HH:mm:ss'))</p>
</div>
<p class="found">Found $($Results.Count) inactive user(s):</p>
<table>
<tr><th>SamAccountName</th><th>Name</th><th>Enabled</th><th class="center">Days Since Last Logon</th><th>Last Logon Date</th><th>Account Created</th><th class="center">Password Never Expires</th><th>Privileged Groups</th></tr>
$HtmlRows
</table>
<div class="legend"><span class="item"><span class="swatch" style="background:#3a1414;"></span>Member of a privileged group</span><span class="item"><span class="swatch" style="background:#332b00;"></span>Password never expires</span></div>
</body></html>
"@
    }

    if (-not (Test-ADModuleAvailable)) {
        Write-Host 'The ActiveDirectory PowerShell module is not installed. Install RSAT-AD-PowerShell and try again.' -ForegroundColor $Theme.Error
        return
    }

    $RunDate = Get-Date
    $CutoffDate = $RunDate.AddMonths(-$MonthsInactive)
    $Properties = @('SamAccountName','Name','Enabled','LastLogonTimestamp','whenCreated','PasswordNeverExpires')
    $AdParams = @{ Filter='*'; Properties=$Properties }
    if ($SearchBase) { $AdParams.SearchBase = $SearchBase }

    try { $AllUsers = Get-ADUser @AdParams } catch {
        Write-Host "Failed to query Active Directory: $_" -ForegroundColor $Theme.Error
        return
    }
    if (-not $IncludeDisabled) { $AllUsers = $AllUsers | Where-Object { $_.Enabled -eq $true } }

    Write-Host 'Checking privileged group membership...' -ForegroundColor $Theme.Muted
    $PrivilegedLookup = Get-PrivilegedMembershipLookup -GroupNames $PrivilegedGroupNames

    $Results = foreach ($User in $AllUsers) {
        if ($Accurate) { $LastLogonDate = Get-AccurateLastLogon -SamAccountName $User.SamAccountName }
        elseif ($User.LastLogonTimestamp) { $LastLogonDate = [DateTime]::FromFileTime($User.LastLogonTimestamp) }
        else { $LastLogonDate = $null }

        $IsStale = if ($null -eq $LastLogonDate) { $User.whenCreated -lt $CutoffDate } else { $LastLogonDate -lt $CutoffDate }
        if ($IsStale) {
            if ($LastLogonDate) { $DaysSince = (New-TimeSpan -Start $LastLogonDate -End $RunDate).Days; $LastLogonDisplay = $LastLogonDate.ToString('dd\/MM\/yyyy') }
            else { $DaysSince = (New-TimeSpan -Start $User.whenCreated -End $RunDate).Days; $LastLogonDisplay = 'Never' }
            $PrivilegedGroupsForUser = if ($PrivilegedLookup.ContainsKey($User.SamAccountName)) { ($PrivilegedLookup[$User.SamAccountName] | Sort-Object -Unique) -join ', ' } else { '' }
            [PSCustomObject]@{
                SamAccountName=$User.SamAccountName; Name=$User.Name; Enabled=$User.Enabled
                'Days Since Last Logon'=$DaysSince; 'Last Logon Date'=$LastLogonDisplay
                'Account Created'=$User.whenCreated.ToString('dd\/MM\/yyyy'); 'Password Never Expires'=$User.PasswordNeverExpires
                'Privileged Groups'=$PrivilegedGroupsForUser
            }
        }
    }

    $Results = $Results | Sort-Object 'Days Since Last Logon' -Descending
    Clear-Host
    Write-Host ''
    Write-Host 'Active Directory Inactive User Report' -ForegroundColor $Theme.Title
    Write-Host ('=' * 40) -ForegroundColor $Theme.Title
    Write-Host ''
    Write-Host ("{0,-18}: {1}" -f "Today's date", $RunDate.ToString('dd\/MM\/yyyy HH:mm:ss')) -ForegroundColor $Theme.Text
    Write-Host ("{0,-18}: {1}" -f 'Inactivity period', "$MonthsInactive months") -ForegroundColor $Theme.Text
    Write-Host ("{0,-18}: {1}" -f 'Cutoff date', $CutoffDate.ToString('dd\/MM\/yyyy HH:mm:ss')) -ForegroundColor $Theme.Text
    Write-Host ''
    Write-Host "Found $($Results.Count) inactive user(s):" -ForegroundColor $Theme.Warn
    Write-Host ''
    Show-BorderedTable -InputObject $Results -Columns @('SamAccountName','Name','Enabled','Days Since Last Logon','Last Logon Date','Account Created','Password Never Expires','Privileged Groups') -CenterColumns @('Days Since Last Logon')

    if (-not $OutputCsvPath) { $OutputCsvPath = ".\${OutputFilePrefix}_$(Get-Date -Format 'yyyyMMdd').csv" }
    $Results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host "Results exported to: $OutputCsvPath" -ForegroundColor $Theme.Success

    if (-not $OutputHtmlPath) { $OutputHtmlPath = ".\${OutputFilePrefix}_$(Get-Date -Format 'yyyyMMdd').html" }
    $HtmlReport = ConvertTo-InactiveUserHtmlReport -Results $Results -RunDate $RunDate -CutoffDate $CutoffDate -MonthsInactive $MonthsInactive
    $HtmlReport | Out-File -FilePath $OutputHtmlPath -Encoding UTF8
    Write-Host "HTML report exported to: $OutputHtmlPath" -ForegroundColor $Theme.Success
}
