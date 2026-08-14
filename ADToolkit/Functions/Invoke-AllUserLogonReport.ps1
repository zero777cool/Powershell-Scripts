<#
.SYNOPSIS
    Reports every Active Directory user with enabled status and LastLogon date.

.DESCRIPTION
    Queries every reachable Domain Controller for the non-replicated LastLogon attribute and keeps
    the newest value for each user. The report contains only SamAccountName, Enabled, and LastLogon.

    LastLogon is displayed as a date only (yyyy-MM-dd). The toolkit does not include time values in
    reports unless explicitly requested.

    Output is always written beneath ADToolkit\Reports\AllUserLogonReport, regardless of the current
    working directory.

.NOTES
    Public function: Invoke-AllUserLogonReport
    Part of: Rance Timber AD Toolkit
    Read-only against Active Directory.
#>

function Invoke-AllUserLogonReport {
    [CmdletBinding()]
    param()

    $OutputDirectory = Join-Path -Path $ADToolkitConfig.ReportsDirectory -ChildPath $ADToolkitConfig.AllUserLogonReport.OutputDirectoryName
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }

    $OutputPath = Join-Path -Path $OutputDirectory -ChildPath "$($ADToolkitConfig.AllUserLogonReport.OutputFilePrefix)_$(Get-Date -Format 'yyyyMMdd').csv"

    try {
        $DomainControllers = @(Get-ADDomainController -Filter * -ErrorAction Stop)
    }
    catch {
        Write-Host "Failed to discover Domain Controllers: $_" -ForegroundColor $Theme.Error
        return
    }

    if ($DomainControllers.Count -eq 0) {
        Write-Host 'No Domain Controllers were discovered.' -ForegroundColor $Theme.Error
        return
    }

    $UsersBySamAccountName = @{}
    Write-Host "Querying $($DomainControllers.Count) Domain Controller(s) for exact LastLogon values..." -ForegroundColor $Theme.Muted

    foreach ($DomainController in $DomainControllers) {
        Write-Host "  $($DomainController.HostName)" -ForegroundColor $Theme.Muted
        try {
            $Users = Get-ADUser -Filter * -Server $DomainController.HostName -Properties Enabled, LastLogon, SamAccountName -ErrorAction Stop
            foreach ($User in $Users) {
                $Existing = $UsersBySamAccountName[$User.SamAccountName]
                if ($null -eq $Existing) {
                    $UsersBySamAccountName[$User.SamAccountName] = [PSCustomObject]@{
                        SamAccountName = $User.SamAccountName
                        Enabled        = $User.Enabled
                        LastLogon      = if ($User.LastLogon) { [DateTime]::FromFileTime($User.LastLogon).Date } else { $null }
                    }
                }
                elseif ($User.LastLogon -and ($null -eq $Existing.LastLogon -or [DateTime]::FromFileTime($User.LastLogon).Date -gt $Existing.LastLogon)) {
                    $Existing.LastLogon = [DateTime]::FromFileTime($User.LastLogon).Date
                }
            }
        }
        catch {
            Write-Warning "Could not query $($DomainController.HostName): $($_.Exception.Message)"
        }
    }

    $Results = @($UsersBySamAccountName.Values | Sort-Object SamAccountName | ForEach-Object {
        [PSCustomObject]@{
            SamAccountName = $_.SamAccountName
            Enabled        = $_.Enabled
            LastLogon      = if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd') } else { $null }
        }
    })

    $Results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

    Clear-Host
    Write-Host ''
    Write-Host 'Active Directory - All User Logon Report' -ForegroundColor $Theme.Title
    Write-Host ('=' * 42) -ForegroundColor $Theme.Title
    Write-Host ''
    Write-Host "Users found : $($Results.Count)" -ForegroundColor $Theme.Text
    Write-Host "DCs queried : $($DomainControllers.Count)" -ForegroundColor $Theme.Text
    Write-Host ''
    Show-BorderedTable -InputObject $Results -Columns @('SamAccountName','Enabled','LastLogon')
    Write-Host ''
    Write-Host "Report exported to: $OutputPath" -ForegroundColor $Theme.Success
}
