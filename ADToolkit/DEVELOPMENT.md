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
│   └── Invoke-ADPrivilegeAudit.ps1
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
- The toolkit is intended to be read-only against Active Directory unless a future feature explicitly documents otherwise.

## Naming standards

Use approved PowerShell verb-noun names and the `Invoke-*` pattern for executable toolkit commands.

Examples:

- `Invoke-InactiveUserReport.ps1` -> `Invoke-InactiveUserReport`
- `Invoke-ADPrivilegeAudit.ps1` -> `Invoke-ADPrivilegeAudit`

Avoid legacy or inconsistent names such as `Audit-ADPrivileges.ps1` for new toolkit features.

## Configuration

Prefer `Config.ps1` for defaults that should be consistent across reports. Do not duplicate the same configurable value in multiple feature scripts.

Feature parameters should still allow an operator to override a useful runtime setting where appropriate.

## Parameters and output

Use clear, consistent parameter names. Where applicable, prefer:

- `-SearchBase`
- `-DomainController`
- `-Credential`
- `-OutputCsvPath`
- `-OutputHtmlPath`
- `-OutputDirectory`

Reports should clearly identify where output was written and should use an `ADToolkit-*` filename prefix by default.

## Safety

AD reporting commands should default to read-only operations. Do not add account modification, group membership changes, password resets, deletion, or other write operations without explicitly documenting the behaviour and getting approval for the change.

## Validation

Before committing changes, run the lightweight static validation script:

```powershell
.\Tests\Validate-ADToolkit.ps1
```

It checks file presence, naming conventions, duplicate public commands, and PowerShell parser errors.

### Future Pester tests

Pester is intentionally **not required yet**. It is a planned later iteration for behavioural/unit tests. Do not remove this note: future LLMs should treat Pester as a planned enhancement rather than introducing a competing test framework.

When Pester is introduced, prefer tests that mock Active Directory calls so tests do not modify or depend on production AD data.

## LLM instructions

When another LLM modifies this project:

1. Read this file and `README.md` first.
2. Preserve the `ADToolkit.ps1` launcher architecture.
3. Do not reintroduce standalone auto-executing feature scripts.
4. Follow the `Invoke-*` naming convention.
5. Reuse `Common.ps1` before creating duplicate helpers.
6. Put shared defaults in `Config.ps1`.
7. Keep AD operations read-only unless explicitly approved.
8. Run `Tests\Validate-ADToolkit.ps1` before declaring the change complete.
9. Keep Pester in mind as the planned future behavioural test framework.
10. Update documentation when adding or changing a feature.
