<#
ADToolkit shared configuration.

Keep feature-specific defaults here when they are intended to be consistent across the toolkit.
Feature scripts should consume these values rather than duplicating them.

All generated reports/logs belong under ADToolkit\Reports regardless of the directory from which
ADToolkit.ps1 is launched. Do not use the current working directory for generated output.

Report date values are date-only by default and use the display format `dd MMM yyyy`.
Do not add time values to reports unless explicitly requested.
#>

$ADToolkitRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ADToolkitReportsRoot = Join-Path -Path $ADToolkitRoot -ChildPath 'Reports'
$ADToolkitReportRoot = $ADToolkitReportsRoot

$ADToolkitConfig = [ordered]@{
    RootDirectory    = $ADToolkitRoot
    ReportsDirectory = $ADToolkitReportsRoot
    ReportDateFormat = 'dd MMM yyyy'

    InactiveUserReport = [ordered]@{
        MonthsInactive       = 6
        PrivilegedGroupNames = @(
            'Domain Admins'
            'Enterprise Admins'
            'Schema Admins'
            'Administrators'
            'Account Operators'
            'Backup Operators'
            'Server Operators'
            'Print Operators'
            'Group Policy Creator Owners'
        )
        OutputDirectoryName  = 'InactiveUserReport'
        OutputFilePrefix     = 'ADToolkit-InactiveUsers'
    }

    ADPrivilegeAudit = [ordered]@{
        DefaultThrottleLimit = 24
        OutputDirectoryName  = 'ADPrivilegeAudit'
        OutputFilePrefix     = 'ADToolkit-PrivilegeAudit'
        LogDirectoryName     = 'Logs'
    }

    AllUserLogonReport = [ordered]@{
        OutputDirectoryName = 'AllUserLogonReport'
        OutputFilePrefix    = 'ADToolkit-AllUserLogons'
    }

    M365AccountComparison = [ordered]@{
        OutputDirectoryName = 'M365AccountComparison'
        OutputFilePrefix    = 'ADToolkit-M365AccountComparison'
        GraphScopes         = @('User.Read.All')
    }
}
