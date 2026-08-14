<#
ADToolkit shared configuration.

Keep feature-specific defaults here when they are intended to be consistent across the toolkit.
Feature scripts should consume these values rather than duplicating them.
#>

$ADToolkitConfig = [ordered]@{
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
        OutputFilePrefix     = 'ADToolkit-InactiveUsers'
    }
}
