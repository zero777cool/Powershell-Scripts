<#
.SYNOPSIS
    Compares on-premises AD SamAccountName values with Microsoft 365 / Entra ID users.

.DESCRIPTION
    Connects interactively to Microsoft Graph using delegated User.Read.All permission and
    compares each on-premises AD user's SamAccountName with the Microsoft Graph
    onPremisesSamAccountName property.

    The report is designed for both IT and HR review. CSV headings use plain-language terms
    while retaining the underlying account identifiers needed for reconciliation.

    The report identifies whether each on-premises account has a corresponding Microsoft 365
    user and shows the user's full name, Microsoft 365 sign-in name, enabled state, and
    synchronization state.

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
        $AdUsers = Get-ADUser -Filter * -Properties Enabled,SamAccountName,GivenName,Surname,Name | Sort-Object SamAccountName
        $M365Users = Get-MgUser -All -Property 'id,displayName,givenName,surname,userPrincipalName,accountEnabled,onPremisesSamAccountName,onPremisesSyncEnabled'
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

        $FullName = if ($M365User -and -not [string]::IsNullOrWhiteSpace($M365User.DisplayName)) {
            $M365User.DisplayName
        }
        elseif ($AdUser.GivenName -or $AdUser.Surname) {
            (@($AdUser.GivenName, $AdUser.Surname) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
        }
        else {
            $AdUser.Name
        }

        [PSCustomObject]@{
            'Full Name' = $FullName
            'AD Network Username' = $AdUser.SamAccountName
            'AD Account Status' = if ($AdUser.Enabled) { 'Enabled' } else { 'Disabled' }
            'Microsoft 365 Account Exists' = if ($M365User) { 'Yes' } else { 'No' }
            'Microsoft 365 Sign-In Name' = if ($M365User) { $M365User.UserPrincipalName } else { '' }
            'Microsoft 365 Account Status' = if ($M365User) { if ($M365User.AccountEnabled) { 'Enabled' } else { 'Disabled' } } else { 'Not Applicable' }
            'Microsoft 365 Account Synced from AD' = if ($M365User) { if ($M365User.OnPremisesSyncEnabled) { 'Yes' } else { 'No' } } else { 'Not Applicable' }
        }
    }

    $Results = $Results | Sort-Object @{ Expression = { if ($_.'AD Account Status' -eq 'Enabled') { 0 } else { 1 } } }, 'Full Name', 'AD Network Username'

    Clear-Host
    Write-Host ''
    Write-Host 'Microsoft 365 Account Comparison' -ForegroundColor $Theme.Title
    Write-Host ('=' * 40) -ForegroundColor $Theme.Title
    Write-Host ''
    Write-Host "Microsoft 365 users retrieved: $($M365Users.Count)" -ForegroundColor $Theme.Text
    Write-Host "On-premises AD users retrieved: $($AdUsers.Count)" -ForegroundColor $Theme.Text
    Write-Host "AD users with M365 accounts: $(($Results | Where-Object { $_.'Microsoft 365 Account Exists' -eq 'Yes' }).Count)" -ForegroundColor $Theme.Success
    Write-Host "AD users without M365 accounts: $(($Results | Where-Object { $_.'Microsoft 365 Account Exists' -eq 'No' }).Count)" -ForegroundColor $Theme.Warn
    Write-Host ''

    Show-BorderedTable -InputObject $Results -Columns @('Full Name','AD Network Username','AD Account Status','Microsoft 365 Account Exists','Microsoft 365 Sign-In Name','Microsoft 365 Account Status','Microsoft 365 Account Synced from AD')

    if (-not $OutputCsvPath) {
        $OutputCsvPath = Join-Path $ADToolkitConfig.ReportsDirectory "M365AccountComparison\ADToolkit-M365AccountComparison_$(Get-Date -Format 'yyyyMMdd').csv"
    }

    $OutputDirectory = Split-Path -Parent $OutputCsvPath
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host "Results exported to: $OutputCsvPath" -ForegroundColor $Theme.Success
}
