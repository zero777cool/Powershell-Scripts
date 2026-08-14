<#
ADToolkit shared configuration.

Keep feature-specific defaults here when they are intended to be consistent across the toolkit.
Feature scripts should consume these values rather than duplicating them.

All generated reports/logs belong under ADToolkit\Reports regardless of the directory from which
ADToolkit.ps1 is launched. Do not use the current working directory for generated output.
#>

$ADToolkitRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ADToolkitReportsRoot = Join-Path -Path $ADToolkitRoot -ChildPath 'Reports'

$ADToolkitConfig = [ordered]@{
    RootDirectory    = $ADToolkitRoot
    ReportsDirectory = $ADToolkitReportsRoot

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
}
