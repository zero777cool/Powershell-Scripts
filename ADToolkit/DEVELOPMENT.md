# ADToolkit Development Guide

This document is intentionally written for both humans and coding LLMs. Read it before modifying the ADToolkit.

## Architecture

```text
ADToolkit/
├── ADToolkit.ps1
├── Config.ps1
├── README.md
├── DEVELOPMENT.md
├── Functions/
│   ├── Common.ps1
│   ├── Invoke-InactiveUserReport.ps1
│   ├── Invoke-ADPrivilegeAudit.ps1
│   ├── Invoke-AllUserLogonReport.ps1
│   └── Invoke-M365AccountComparison.ps1
└── Tests/
    └── Validate-ADToolkit.ps1
```

- `ADToolkit.ps1` is the menu-driven launcher only.
- `Config.ps1` contains shared/default configuration.
- `Functions/Common.ps1` contains reusable UI, formatting, HTML styling, and prerequisite helpers.
- Each feature belongs in its own `Functions/Invoke-*.ps1` file.
- Each feature file should expose one public `Invoke-*` function whose name matches the filename.
- Private helper functions should remain inside the feature file unless they are genuinely shared.
- Feature scripts must not execute their report automatically when dot-sourced.
- The toolkit is intended to be read-only against Active Directory and Microsoft 365 unless a future feature explicitly documents otherwise.

## Naming standards

Use approved PowerShell verb-noun names and the `Invoke-*` pattern for executable toolkit commands.

Examples:

- `Invoke-InactiveUserReport.ps1` -> `Invoke-InactiveUserReport`
- `Invoke-ADPrivilegeAudit.ps1` -> `Invoke-ADPrivilegeAudit`
- `Invoke-AllUserLogonReport.ps1` -> `Invoke-AllUserLogonReport`
- `Invoke-M365AccountComparison.ps1` -> `Invoke-M365AccountComparison`

Avoid legacy or inconsistent names such as `Audit-ADPrivileges.ps1` for new toolkit features.

## Configuration

Prefer `Config.ps1` for defaults that should be consistent across reports. Do not duplicate the same configurable value in multiple feature scripts.

Feature parameters should still allow an operator to override a useful runtime setting where appropriate.

## Dates and times

**Toolkit-wide rule:** report date values are date-only by default and use the display format **`dd MMM yyyy`**, for example `14 Aug 2026`.

Do **not** add time values to reports unless the user explicitly requests time. This rule exists so CSV reports remain human-readable and less ambiguous when opened in applications with different regional date settings.

The toolkit may retain timestamps internally where required for calculations or operational logging, but user-facing report fields should not expose time unless explicitly requested.

## Parameters and output

Use clear, consistent parameter names. Where applicable, prefer:

- `-SearchBase`
- `-DomainController`
- `-Credential`
- `-OutputCsvPath`
- `-OutputHtmlPath`
- `-OutputDirectory`

Reports should clearly identify where output was written and should use an `ADToolkit-*` filename prefix by default.

All generated reports and logs must be written beneath `ADToolkit\Reports`, using paths derived from `$PSScriptRoot`/the toolkit root. Never use the current working directory as the default report location.

## Safety

AD reporting commands should default to read-only operations. Do not add account modification, group membership changes, password resets, deletion, or other write operations without explicitly documenting the behaviour and getting approval for the change.

## Current reports

### All User Logon Report

`Invoke-AllUserLogonReport` lists every domain user with only `SamAccountName`, `Enabled`, and the exact `LastLogon` value. Because `LastLogon` is not replicated, the command queries every reachable Domain Controller and keeps the newest value for each account. The report is written beneath `ADToolkit\Reports\AllUserLogonReport`.

### Inactive User Report

`Invoke-InactiveUserReport` identifies stale accounts using the configured inactivity period. Its user-facing date fields should follow the toolkit-wide `dd MMM yyyy` date-only rule.

### Microsoft 365 Account Comparison

`Invoke-M365AccountComparison` compares on-premises AD `SamAccountName` values with Microsoft Graph `onPremisesSamAccountName` values. This is the direct synchronized attribute Microsoft Graph exposes for on-premises `samAccountName` values. citeturn0search3

The feature is read-only and uses interactive delegated Microsoft Graph authentication with `User.Read.All`. It should connect to Graph only when option 4 is selected; the other reports must remain independent of Microsoft Graph. citeturn0search0turn0search7

Do not add Microsoft Graph write permissions to this feature. If future Microsoft 365 functionality requires writes, treat that as a separate, explicitly approved design change.

## Planned development environment

The project should eventually have a controlled Windows PowerShell test environment available for deeper testing. This is intentionally deferred for now.

Planned approach:

1. Keep GitHub Actions as the first automated validation layer.
2. Add a local Windows test runner for tests requiring PowerShell/RSAT and real AD connectivity.
3. Use the local environment to validate Domain Controller discovery, ActiveDirectory queries, CIM/DCOM access, local Administrators enumeration, real report generation, and Microsoft Graph authentication/API calls.
4. Do not expose WinRM/PowerShell directly to the public internet for this purpose; use a controlled local development/agent mechanism if remote execution is later introduced.

This plan should be revisited soon. Do not remove it from the documentation unless the project direction changes.

## Validation

Before committing changes, run the lightweight static validation script:

```powershell
.\Tests\Validate-ADToolkit.ps1
```

It checks file presence, naming conventions, duplicate public commands, and PowerShell parser errors.

### Future Pester tests

Pester is intentionally **not required yet**. It is a planned later iteration for behavioural/unit tests. Do not remove this note: future LLMs should treat Pester as a planned enhancement rather than introducing a competing test framework.

When Pester is introduced, prefer tests that mock Active Directory and Microsoft Graph calls so tests do not modify or depend on production directory data.

## LLM instructions

When another LLM modifies this project:

1. Read this file and `README.md` first.
2. Preserve the `ADToolkit.ps1` launcher architecture.
3. Do not reintroduce standalone auto-executing feature scripts.
4. Follow the `Invoke-*` naming convention.
5. Reuse `Common.ps1` before creating duplicate helpers.
6. Put shared defaults in `Config.ps1`.
7. Keep AD and Microsoft 365 operations read-only unless explicitly approved.
8. Keep all generated reports/logs beneath `ADToolkit\Reports` and never default to the caller's current directory.
9. Use date-only report values in `dd MMM yyyy` format and never add report times unless explicitly requested.
10. Run `Tests\Validate-ADToolkit.ps1` before declaring the change complete.
11. Keep Pester in mind as the planned future behavioural test framework.
12. Keep the planned Windows local test environment in mind for a later iteration.
13. Update documentation when adding or changing a feature.
