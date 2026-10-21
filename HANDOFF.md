# Handoff — Scripting (zero777cool/Powershell-Scripts)

**Last close-out:** 2026-10-17 15:57 · **Branch:** `main` · **Base:** `main`

## Done this session
Built from the repo state, not a full chat record.
- ADToolkit: new `Invoke-ActiveUserReport.ps1` (menu key 5, "Active Domain Users (HR Payroll List)": enabled users with name, username, email, created date; CSV + HTML, read-only).
- ADToolkit: new `Invoke-CsvToHtmlRebuild.ps1` (menu key R: regenerate HTML from an edited CSV; handles comma/semicolon CSVs).
- `Config.ps1`: added `ReportTitles` and `ActiveUserReport` settings.
- `Common.ps1` (+115 lines), `ADToolkit.ps1` menu entries and a VPN reminder note.
- Small edits to the AllUserLogon, M365AccountComparison, UserLogonLocation and ADPrivilegeAudit reports, plus README, DEVELOPMENT.md and the validation test.

## Where we left off
All of the above was uncommitted on `main` and is now committed and pushed. It has not been confirmed that it was run against live AD.

## Next steps
1. (proposed) Run `ADToolkit/Tests/Validate-ADToolkit.ps1` and try menu options 5 and R on a domain-joined machine.
2. (proposed) Check that the HTML reports from the other options still render with the new `ReportTitles`.

## Open questions / blockers
- None recorded.

## To resume
```powershell
cd $HOME\Downloads\Github\Scripting
git fetch
git switch main
git pull
```

## Notes for Claude
- Files are CRLF on the PC. Commits from the sandbox normalise to LF (`core.autocrlf=input`), so expect line-ending warnings, not real diffs.
- Read ADToolkit/DEVELOPMENT.md before changing the toolkit.
