<#
.SYNOPSIS
    Finds Active Directory computers where a specified user currently has an interactive logon session.

.DESCRIPTION
    Prompts for an Active Directory SamAccountName, queries enabled computer objects, and inspects
    Win32_LogonSession and Win32_LoggedOnUser associations on each reachable computer. Interactive
    (console) and Remote Interactive (RDP) sessions are included. Unreachable computers are skipped
    so a single offline device does not stop the report.

    The report is read-only and is always written beneath ADToolkit\Reports\UserLogonLocationReport,
    regardless of the current working directory.

.PARAMETER SamAccountName
    The Active Directory SamAccountName to look for. If omitted, the command prompts for it.

.PARAMETER OutputCsvPath
    Optional CSV output path. By default the report is written beneath ADToolkit\Reports.

.NOTES
    Public function: Invoke-UserLogonLocationReport
    Part of: Rance Timber AD Toolkit
    Read-only against Active Directory and remote computers.
#>

function Invoke-UserLogonLocationReport {
    [CmdletBinding()]
    param(
        [string]$SamAccountName,
        [string]$OutputCsvPath
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-Host 'The ActiveDirectory PowerShell module is not installed. Install RSAT-AD-PowerShell and try again.' -ForegroundColor $Theme.Error
        return
    }

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        $SamAccountName = Read-Host 'Enter the AD network username (SamAccountName)'
    }

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        Write-Host 'An AD network username is required.' -ForegroundColor $Theme.Error
        return
    }

    try {
        $TargetUser = Get-ADUser -Identity $SamAccountName -Properties DisplayName, SamAccountName -ErrorAction Stop
        $Domain = Get-ADDomain -ErrorAction Stop
        $Computers = @(Get-ADComputer -Filter 'Enabled -eq $true' -Properties DNSHostName -ErrorAction Stop)
    }
    catch {
        Write-Host "Could not retrieve Active Directory information: $($_.Exception.Message)" -ForegroundColor $Theme.Error
        return
    }

    $OutputDirectory = Join-Path -Path $ADToolkitConfig.ReportsDirectory -ChildPath $ADToolkitConfig.UserLogonLocationReport.OutputDirectoryName
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    }

    if (-not $OutputCsvPath) {
        $OutputCsvPath = Join-Path -Path $OutputDirectory -ChildPath "$($ADToolkitConfig.UserLogonLocationReport.OutputFilePrefix)_$(Get-Date -Format 'yyyyMMdd').csv"
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $UnreachableCount = 0
    $ScannedCount = 0
    $SessionTypes = @{ 2 = 'Interactive'; 10 = 'Remote Interactive (RDP)' }

    Write-Host "Checking $($Computers.Count) enabled computer(s) for $($TargetUser.SamAccountName)..." -ForegroundColor $Theme.Muted

    foreach ($Computer in $Computers) {
        $ComputerTarget = if ($Computer.DNSHostName) { $Computer.DNSHostName } else { $Computer.Name }
        $CimSession = $null

        try {
            $CimSession = New-CimSession -ComputerName $ComputerTarget -ErrorAction Stop
            $LogonSessions = Get-CimInstance -CimSession $CimSession -ClassName Win32_LogonSession -Filter 'LogonType = 2 OR LogonType = 10' -ErrorAction Stop
            $ScannedCount++

            foreach ($LogonSession in $LogonSessions) {
                $Accounts = Get-CimAssociatedInstance -InputObject $LogonSession -Association Win32_LoggedOnUser -ResultClassName Win32_Account -ErrorAction Stop
                foreach ($Account in $Accounts) {
                    if ($Account.Name -ieq $TargetUser.SamAccountName -and $Account.Domain -ieq $Domain.NetBIOSName) {
                        $Results.Add([PSCustomObject]@{
                            'Full Name'           = $TargetUser.DisplayName
                            'AD Network Username' = $TargetUser.SamAccountName
                            'Computer Name'       = $Computer.Name
                            'Session Type'        = $SessionTypes[[int]$LogonSession.LogonType]
                        })
                    }
                }
            }
        }
        catch {
            $UnreachableCount++
            Write-Warning "Could not query ${ComputerTarget}: $($_.Exception.Message)"
        }
        finally {
            if ($CimSession) {
                Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
            }
        }
    }

    $Results = @($Results | Sort-Object 'Computer Name', 'Session Type' -Unique)
    $Results | Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding UTF8

    Clear-Host
    Write-Host ''
    Write-Host 'Find User Logon Location' -ForegroundColor $Theme.Title
    Write-Host ('=' * 24) -ForegroundColor $Theme.Title
    Write-Host ''
    Write-Host "Full name           : $($TargetUser.DisplayName)" -ForegroundColor $Theme.Text
    Write-Host "Network username    : $($TargetUser.SamAccountName)" -ForegroundColor $Theme.Text
    Write-Host "Computers checked   : $ScannedCount" -ForegroundColor $Theme.Text
    Write-Host "Computers unavailable: $UnreachableCount" -ForegroundColor $Theme.Text
    Write-Host ''

    if ($Results.Count -gt 0) {
        Write-Host "Current session(s) found: $($Results.Count)" -ForegroundColor $Theme.Success
        Show-BorderedTable -InputObject $Results -Columns @('Full Name','AD Network Username','Computer Name','Session Type')
    }
    else {
        Write-Host 'No interactive or Remote Desktop sessions were found for this user.' -ForegroundColor $Theme.Warn
    }

    Write-Host ''
    Write-Host "Report exported to: $OutputCsvPath" -ForegroundColor $Theme.Success
}
