# AD Toolkit

A menu-driven launcher for Active Directory reporting scripts. Run `ADToolkit.ps1` and pick a command from the menu instead of remembering separate script names/paths.

## Layout

```text
ADToolkit/
├── ADToolkit.ps1                        <- launcher/menu
├── Config.ps1                           <- shared/default configuration
├── Functions/
│   ├── Common.ps1                       <- shared theme, HTML CSS, and helper functions
│   ├── Invoke-InactiveUserReport.ps1    <- inactive account report
│   ├── Invoke-ADPrivilegeAudit.ps1      <- privileged access audit
│   ├── Invoke-AllUserLogonReport.ps1    <- all users and exact LastLogon report
│   └── Invoke-M365AccountComparison.ps1 <- AD to Microsoft 365 account comparison
├── Reports/                             <- generated reports/logs; never committed
├── Tests/
│   └── Validate-ADToolkit.ps1           <- lightweight static validation
├── DEVELOPMENT.md                       <- architecture and LLM development rules
└── README.md
```

## Running it

```powershell
.\ADToolkit.ps1
```

Requires the ActiveDirectory PowerShell module (RSAT-AD-PowerShell). The toolkit checks for it on startup and tells you if it is missing.

**Run location does not affect report output.** All generated reports and audit logs are written beneath `ADToolkit\Reports` using paths based on the toolkit's own directory, not the current working directory.

```text
ADToolkit\Reports\
├── InactiveUserReport\
├── ADPrivilegeAudit\
│   └── Logs\
├── AllUserLogonReport\
└── M365AccountComparison\
```

The `Reports` tree is excluded by the repository `.gitignore` and must never be committed.

## Current commands

### 1. Inactive User Report

Runs `Invoke-InactiveUserReport` and identifies accounts that have been inactive for the configured period. It supports disabled-account inclusion, OU/SearchBase filtering, accurate LastLogon collection, privileged-group highlighting, CSV output, and HTML output.

Default output names use the `ADToolkit-InactiveUsers_yyyyMMdd` prefix.

### 2. AD Privilege Audit

Runs `Invoke-ADPrivilegeAudit` and audits privileged AD groups, nested membership paths, and local Administrators membership on enabled domain computers. The audit is read-only and produces CSV reports; an Excel workbook is also produced when `ImportExcel` is available.

The audit requires PowerShell 5.1+, the ActiveDirectory/RSAT module, and remote CIM/DCOM access for the local Administrators scan.

### 3. All User Logon Report

Runs `Invoke-AllUserLogonReport` and lists every domain user with only:

- `SamAccountName`
- `Enabled`
- `LastLogon`

The report uses the exact, non-replicated `LastLogon` attribute. Because `LastLogon` is maintained independently on each Domain Controller, the command queries every reachable Domain Controller and keeps the newest value for each account.

The CSV is written to `ADToolkit\Reports\AllUserLogonReport` regardless of where the toolkit is launched from.

### 4. Microsoft 365 Account Comparison

Runs `Invoke-M365AccountComparison` and compares each on-premises AD `SamAccountName` with the Microsoft Graph `onPremisesSamAccountName` property. Microsoft documents `onPremisesSamAccountName` as the synchronized on-premises `samAccountName` value and notes that it is populated for directories synchronized to Microsoft Entra ID with Microsoft Entra Connect. citeturn0search3

The report shows:

- `SamAccountName`
- `AD Enabled`
- `M365 Account`
- `M365 UPN`
- `M365 Enabled`
- `M365 Synced`

Option 4 is read-only. It uses interactive Microsoft Graph PowerShell delegated authentication with `User.Read.All`. Microsoft documents `Connect-MgGraph -Scopes` for interactive delegated authentication and `Get-MgUser -All` for retrieving tenant users. citeturn0search0turn0search4

Install the required module if necessary:

```powershell
Install-Module Microsoft.Graph.Users -Scope CurrentUser
```

The toolkit only connects to Microsoft Graph when option 4 is selected. The other ADToolkit reports do not require Microsoft Graph.

The report is written to `ADToolkit\Reports\M365AccountComparison`.

## Configuration

Shared defaults are stored in `Config.ps1`.

Keep recurring values that are actually shared between reports in configuration rather than duplicating them. Feature parameters should still provide sensible runtime overrides where appropriate.

## Adding a new command

1. Create `Functions\Invoke-YourReport.ps1`.
2. Expose exactly one public function named `Invoke-YourReport`.
3. Keep feature-specific helper functions nested inside the public function unless they are genuinely shared.
4. Reuse `Common.ps1` helpers and `$Theme` rather than creating duplicate UI/formatting code.
5. Put shared/default settings in `Config.ps1` when the setting is genuinely shared.
6. Add the feature path to `$RequiredToolkitFiles` in `ADToolkit.ps1`.
7. Add a `Key`, `Title`, `Description`, and `Action` to `$MenuItems`.
8. Update this README when the new command changes the toolkit's user-facing functionality.
9. Run `Tests\Validate-ADToolkit.ps1` before committing.

## Naming standards

Use the PowerShell `Invoke-*` pattern for executable toolkit commands. The filename and public function name must match.

Examples:

```text
Invoke-InactiveUserReport.ps1    -> Invoke-InactiveUserReport
Invoke-ADPrivilegeAudit.ps1      -> Invoke-ADPrivilegeAudit
Invoke-AllUserLogonReport.ps1    -> Invoke-AllUserLogonReport
Invoke-M365AccountComparison.ps1 -> Invoke-M365AccountComparison
```

Do not introduce legacy names such as `Audit-ADPrivileges.ps1` for new commands.

## Date standard

All report dates are date-only and use `dd MMM yyyy`, for example `14 Aug 2026`. Do not include time values unless the user explicitly requests them.

## Safety

ADToolkit reports are intended to be **read-only** against Active Directory and Microsoft 365. Do not add account changes, group membership changes, password resets, deletions, or other write operations without explicitly documenting and approving the behaviour.

## Testing

Run the current lightweight static validation with:

```powershell
.\Tests\Validate-ADToolkit.ps1
```

This validates required files, feature naming, public command names, duplicate public functions, and PowerShell parser errors without connecting to AD or Microsoft Graph.

### Planned: Pester

Pester is intentionally **deferred to a later iteration**. It is the planned behavioural/unit testing framework for this project. Future LLMs should preserve this decision and should not add another test framework in its place.

When introduced, Pester tests should mock AD and Microsoft Graph cmdlets where practical so tests remain safe and do not depend on production directory data.

For contributor/LLM rules, see `DEVELOPMENT.md`.
