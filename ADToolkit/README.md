# Rance Timber AD Toolkit

A menu-driven launcher for Active Directory reporting scripts. Run `ADToolkit.ps1` and pick a
command from the menu instead of remembering separate script names/paths.

## Layout

```
ADToolkit/
├── ADToolkit.ps1                        <- run this. Shows the menu, dispatches to commands.
├── Functions/
│   ├── Common.ps1                       <- shared colour theme, HTML CSS, and helper functions
│   │                                        (Show-Banner, Show-BorderedTable, Wait-KeyPress,
│   │                                        Test-ADModuleAvailable). Loaded automatically first.
│   ├── Invoke-InactiveUserReport.ps1    <- "Inactive User Report" command
│   └── Invoke-ADPrivilegeAudit.ps1      <- "AD Privilege Audit" command
└── README.md
```

## Running it

```powershell
.\ADToolkit.ps1
```

Requires the ActiveDirectory PowerShell module (RSAT-AD-PowerShell). The toolkit checks for it
on startup and tells you if it's missing.

## Adding a new command

1. Copy the pattern in `Functions\Invoke-InactiveUserReport.ps1`: one file, one public function
   matching the filename (e.g. `Functions\Invoke-PasswordExpiryReport.ps1` → function
   `Invoke-PasswordExpiryReport`). Keep any helper functions it needs *nested inside* that
   function so they can't collide with helpers in other command files.
2. Use `$Theme`, `Show-BorderedTable`, `Show-Banner`, and `$HtmlThemeStyle` from `Common.ps1`
   rather than hardcoding colours or writing a new table renderer, so the new command looks
   consistent with the rest of the toolkit.
3. In `ADToolkit.ps1`:
   - Add its relative path (e.g. `'Functions\Invoke-PasswordExpiryReport.ps1'`) to the
     `$RequiredToolkitFiles` array near the top.
   - Add one entry to the `$MenuItems` array with a `Key`, `Title`, `Description`, and an
     `Action` scriptblock that calls your function.

That's the whole process - no changes needed anywhere else.

## Colour theme

Defined once in `Functions\Common.ps1` as `$Theme`:

| Key       | Colour    | Used for                                  |
|-----------|-----------|--------------------------------------------|
| Title     | Cyan      | Banners, headings                          |
| Accent    | Magenta   | Menu option numbers/keys                   |
| Text      | White     | Body/detail text                           |
| Muted     | DarkGray  | Secondary/status text, "press any key"     |
| Warn      | Yellow    | Result counts, warnings                    |
| Error     | Red       | Failures                                   |
| Success   | Green     | Completed exports, confirmations           |

HTML reports share one CSS block (`$HtmlThemeStyle`) so every exported report matches this same
palette.


## AD Privilege Audit

The **AD Privilege Audit** menu option runs `Functions\Invoke-ADPrivilegeAudit.ps1`, exposing the `Invoke-ADPrivilegeAudit` function. It audits privileged AD groups, nested membership paths, and local Administrators membership on enabled domain computers. The audit is read-only and produces CSV reports; an Excel workbook is also produced when `ImportExcel` is available. The audit script requires PowerShell 5.1+, the ActiveDirectory/RSAT module, and remote CIM/DCOM access for the local Administrators scan.
