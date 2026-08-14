# AD Toolkit

A menu-driven launcher for Active Directory reporting scripts. Run `ADToolkit.ps1` and pick a command from the menu instead of remembering separate script names/paths.

## Layout

```text
ADToolkit/
├── ADToolkit.ps1                        <- launcher/menu
├── Config.ps1                           <- shared/default configuration
├── Common/                              <- not used; shared helpers remain in Functions
├── Functions/
│   ├── Common.ps1                       <- shared theme, HTML CSS, and helper functions
│   ├── Invoke-InactiveUserReport.ps1    <- inactive account report
│   └── Invoke-ADPrivilegeAudit.ps1      <- privileged access audit
├── Tests/
│   └── Validate-ADToolkit.ps1           <- lightweight static validation
├── DEVELOPMENT.md                       <- architecture and LLM development rules
└── README.md
```

> Note: `Functions\Common.ps1` is intentionally kept with the feature scripts because the launcher loads the whole `Functions` directory as toolkit command dependencies.

## Running it

```powershell
.\ADToolkit.ps1
```

Requires the ActiveDirectory PowerShell module (RSAT-AD-PowerShell). The toolkit checks for it on startup and tells you if it is missing.

## Current commands

### 1. Inactive User Report

Runs `Invoke-InactiveUserReport` and identifies accounts that have been inactive for the configured period. It supports disabled-account inclusion, OU/SearchBase filtering, accurate LastLogon collection, privileged-group highlighting, CSV output, and HTML output.

Default output names use the `ADToolkit-InactiveUsers_yyyyMMdd` prefix.

### 2. AD Privilege Audit

Runs `Invoke-ADPrivilegeAudit` and audits privileged AD groups, nested membership paths, and local Administrators membership on enabled domain computers. The audit is read-only and produces CSV reports; an Excel workbook is also produced when `ImportExcel` is available.

The audit requires PowerShell 5.1+, the ActiveDirectory/RSAT module, and remote CIM/DCOM access for the local Administrators scan.

## Configuration

Shared defaults are stored in `Config.ps1`.

Keep recurring values such as inactivity thresholds, privileged group lists, default throttling, and output naming in configuration rather than duplicating them inside multiple reports.

Feature parameters should still provide sensible runtime overrides where appropriate.

## Adding a new command

1. Create `Functions\Invoke-YourReport.ps1`.
2. Expose exactly one public function named `Invoke-YourReport`.
3. Keep feature-specific helper functions nested inside the public function unless they are genuinely shared.
4. Reuse `Common.ps1` helpers and `$Theme` rather than creating duplicate UI/formatting code.
5. Put shared/default settings in `Config.ps1`.
6. Add the feature path to `$RequiredToolkitFiles` in `ADToolkit.ps1`.
7. Add a `Key`, `Title`, `Description`, and `Action` to `$MenuItems`.
8. Update this README when the new command changes the toolkit's user-facing functionality.
9. Run `Tests\Validate-ADToolkit.ps1` before committing.

## Naming standards

Use the PowerShell `Invoke-*` pattern for executable toolkit commands. The filename and public function name must match.

Examples:

```text
Invoke-InactiveUserReport.ps1 -> Invoke-InactiveUserReport
Invoke-ADPrivilegeAudit.ps1   -> Invoke-ADPrivilegeAudit
```

Do not introduce legacy names such as `Audit-ADPrivileges.ps1` for new commands.

## Safety

ADToolkit reports are intended to be **read-only** against Active Directory. Do not add account changes, group membership changes, password resets, deletions, or other write operations without explicitly documenting and approving the behaviour.

## Testing

Run the current lightweight static validation with:

```powershell
.\Tests\Validate-ADToolkit.ps1
```

This validates required files, feature naming, public command names, duplicate public functions, and PowerShell parser errors without connecting to AD.

### Planned: Pester

Pester is intentionally **deferred to a later iteration**. It is the planned behavioural/unit testing framework for this project. Future LLMs should preserve this decision and should not add another test framework in its place.

When introduced, Pester tests should mock AD cmdlets where practical so tests remain safe and do not depend on production Active Directory data.

For contributor/LLM rules, see `DEVELOPMENT.md`.
