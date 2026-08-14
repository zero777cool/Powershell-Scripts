<#
.SYNOPSIS
    Compares on-premises AD SamAccountName values with Microsoft 365 / Entra ID users.

.DESCRIPTION
    Connects interactively to Microsoft Graph using delegated User.Read.All permission and
    compares each on-premises AD user's SamAccountName with the Microsoft Graph
    onPremisesSamAccountName property.

    The report identifies whether each on-premises account has a corresponding Microsoft 365
    user and shows the Microsoft 365 UPN, enabled state, and synchronization state.

    This report is read-only. It does not create, modify, disable, or delete Microsoft 365 users.

    Report dates are date-only and use the toolkit standard dd MMM yyyy format. Time values are
    not included unless explicitly requested.

.NOTES
    Part of the ADToolkit.
    Requires Microsoft.Graph.Users and interactive delegated User.Read.All consent.
#>

function Invoke-M365AccountComparison {
    [CmdletBinding()]
    param(
        [string]$OutputCsvPath
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
        Write-Host 'Microsoft.Graph.Users is not installed.' -ForegroundColor $Theme.Error
        Write-Host 'Install it with: Install-Module Microsoft.Graph.Users -Scope CurrentUser' -ForegroundColor $Theme.Warn
        return
    }

    try {
        if (-not (Get-MgContext)) {
            Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor $Theme.Muted
            Connect-MgGraph -Scopes 'User.Read.All' -NoWelcome
        }

        $Context = Get-MgContext
        if (-not $Context) {
            Write-Host 'Microsoft Graph authentication was not completed.' -ForegroundColor $Theme.Error
            return
        }

        Write-Host "Connected to Microsoft Graph tenant: $($Context.TenantId)" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host "Microsoft Graph connection failed: $_" -ForegroundColor $Theme.Error
        return
    }

    try {
        $AdUsers = Get-ADUser -Filter * -Properties Enabled,SamAccountName | Sort-Object SamAccountName
        $M365Users = Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,onPremisesSamAccountName,onPremisesSyncEnabled'
    }
    catch {
        Write-Host "Failed to retrieve account data: $_" -ForegroundColor $Theme.Error
        return
    }

    $M365Lookup = @{}
    foreach ($M365User in $M365Users) {
        if (-not [string]::IsNullOrWhiteSpace($M365User.OnPremisesSamAccountName)) {
            $Key = $M365User.OnPremisesSamAccountName.ToLowerInvariant()
            if (-not $M365Lookup.ContainsKey($Key)) {
                $M365Lookup[$Key] = $M365User
            }
        }
    }

    $Results = foreach ($AdUser in $AdUsers) {
        $Key = $AdUser.SamAccountName.ToLowerInvariant()
        $M365User = $M365Lookup[$Key]

        [PSCustomObject]@{
            SamAccountName = $AdUser.SamAccountName
            'AD Enabled' = $AdUser.Enabled
            'M365 Account' = if ($M365User) { 'YES' } else { 'NO' }
            'M365 UPN' = if ($M365User) { $M365User.UserPrincipalName } else { '' }
            'M365 Enabled' = if ($M365User) { $M365User.AccountEnabled } else { $null }
            'M365 Synced' = if ($M365User) { $M365User.OnPremisesSyncEnabled } else { $null }
        }
    }

    $Results = $Results | Sort-Object @{ Expression = { if ($_.'AD Enabled') { 0 } else { 1 } } }, SamAccountName

    Clear-Host
    Write-Host ''
    Write-Host 'Microsoft 365 Account Comparison' -ForegroundColor $Theme.Title
    Write-Host ('=' * 40) -ForegroundColor $Theme.Title
    Write-Host ''
    Write-Host "Microsoft 365 users retrieved: $($M365Users.Count)" -ForegroundColor $Theme.Text
    Write-Host "On-premises AD users retrieved: $($AdUsers.Count)" -ForegroundColor $Theme.Text
    Write-Host "AD users with M365 accounts: $(($Results | Where-Object { $_.'M365 Account' -eq 'YES' }).Count)" -ForegroundColor $Theme.Success
    Write-Host "AD users without M365 accounts: $(($Results | Where-Object { $_.'M365 Account' -eq 'NO' }).Count)" -ForegroundColor $Theme.Warn
    Write-Host ''

    Show-BorderedTable -InputObject $Results -Columns @('SamAccountName','AD Enabled','M365 Account','M365 UPN','M365 Enabled','M365 Synced')

    if (-not $OutputCsvPath) {
        $OutputCsvPath = Join-Path $ADToolkitReportRoot "M365AccountComparison\ADToolkit-M365AccountComparison_$(Get-Date -Format 'yyyyMMdd').csv"
    }

    $OutputDirectory = Split-Path -Parent $OutputCsvPath
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host "Results exported to: $OutputCsvPath" -ForegroundColor $Theme.Success
}
