<#
.SYNOPSIS
    AD Toolkit command that audits effective Active Directory and local Administrators privileges.

.DESCRIPTION
    Enumerates protected and high-impact AD security groups, nested membership paths, and local
    Administrators membership on AD-joined computers. The command is read-only. CSV output is
    always produced; an Excel workbook is added when ImportExcel is available.

.PARAMETER DomainController
    Fully qualified domain controller to query. Defaults to AD discovery.

.PARAMETER Credential
    Optional credential used for AD cmdlets and remote CIM queries.

.PARAMETER SkipLocalAdministratorScan
    Skips remote local Administrators enumeration.

.PARAMETER InstallImportExcel
    Attempts a CurrentUser installation of ImportExcel if it is absent.

.PARAMETER ThrottleLimit
    Maximum concurrent remote CIM scans. Default: 24.

.NOTES
    Public function: Invoke-ADPrivilegeAudit
    Version: 1.0.1
    Requires: Windows PowerShell 5.1+ or PowerShell 7+ on Windows, RSAT ActiveDirectory module,
    and network access to domain controllers. Remote local-group inventory uses CIM/DCOM.

    This file intentionally contains one public Invoke-* function so it can be dot-sourced by
    ADToolkit.ps1 without executing the audit during toolkit startup.
#>

function Initialize-AuditDirectories {
    [CmdletBinding()]
    param()
    foreach ($directory in @($script:AuditDirectory, $script:LogDirectory)) {
        if (-not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -Path $directory -ItemType Directory -Force
        }
    }
}

function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Information','Warning','Error','Verbose')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$ComputerName
    )
    $entry = '[{0:yyyy-MM-dd HH:mm:ss.fff}] [{1}] {2}{3}' -f (Get-Date), $Level, $(if ($ComputerName) { "[$ComputerName] " } else { '' }), $Message
    Add-Content -LiteralPath $script:LogPath -Value $entry -Encoding UTF8
    switch ($Level) {
        'Warning' { Write-Warning $Message; $script:Warnings.Add([pscustomobject]@{ Time=Get-Date; Computer=$ComputerName; Message=$Message }) }
        'Error'   { Write-Error -Message $Message -ErrorAction Continue; $script:Errors.Add([pscustomobject]@{ Time=Get-Date; Computer=$ComputerName; Message=$Message }) }
        'Verbose' { Write-Verbose $Message }
        default   { Write-Verbose $Message }
    }
}

function Get-ExceptionCategory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Exception]$Exception)
    $message = $Exception.Message
    if ($message -match '(?i)access is denied|unauthorized') { return 'Access denied' }
    if ($message -match '(?i)winrm|wsman') { return 'WinRM failure' }
    if ($message -match '(?i)rpc server|network path|not found|unavailable|timed out|offline|0x800706ba') { return 'Offline or WMI unavailable' }
    if ($message -match '(?i)wmi|cim') { return 'WMI/CIM failure' }
    return 'Query failure'
}

function Add-AuditError {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Stage,[string]$Computer,[Parameter(Mandatory)][System.Exception]$Exception)
    $record = [pscustomobject]@{ Time=Get-Date; Stage=$Stage; Computer=$Computer; Category=(Get-ExceptionCategory -Exception $Exception); Message=$Exception.Message }
    $script:Errors.Add($record)
    Write-AuditLog -Level Error -ComputerName $Computer -Message "${Stage}: $($Exception.Message)"
}

function Import-RequiredModules {
    [CmdletBinding()]
    param()
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        throw 'PowerShell 5.1 or later is required.'
    }
    try { Import-Module -Name ActiveDirectory -ErrorAction Stop } catch {
        throw 'The ActiveDirectory module is required. Install RSAT: Active Directory Domain Services and Lightweight Directory Tools, then run again.'
    }
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) { throw 'The CimCmdlets module is required.' }
    Write-AuditLog -Level Information -Message 'ActiveDirectory and CimCmdlets prerequisites validated.'
}

function Import-ExcelModule {
    [CmdletBinding()]
    param([switch]$AttemptInstall)
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        if (-not $AttemptInstall) { Write-AuditLog -Level Warning -Message 'ImportExcel is not installed. CSV exports will be created; use -InstallImportExcel to attempt a CurrentUser install.'; return $false }
        try {
            if (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue) { Install-PSResource -Name ImportExcel -Scope CurrentUser -TrustRepository -ErrorAction Stop }
            elseif (Get-Command -Name Install-Module -ErrorAction SilentlyContinue) { Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop }
            else { throw 'No PowerShell Gallery package command is available.' }
        } catch { Write-AuditLog -Level Warning -Message "ImportExcel installation failed: $($_.Exception.Message)"; return $false }
    }
    try { Import-Module -Name ImportExcel -ErrorAction Stop; return $true } catch { Write-AuditLog -Level Warning -Message "ImportExcel import failed: $($_.Exception.Message)"; return $false }
}

function Get-AdCommandParameters {
    [CmdletBinding()]
    param()
    $parameters = @{ ErrorAction = 'Stop' }
    if ($script:DomainController) { $parameters.Server = $script:DomainController }
    if ($script:Credential) { $parameters.Credential = $script:Credential }
    return $parameters
}

function Get-ObjectSidString {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Security.Principal.SecurityIdentifier]) { return $Value.Value }
    if ($Value -is [byte[]]) { try { return ([System.Security.Principal.SecurityIdentifier]::new($Value,0)).Value } catch { return $null } }
    return [string]$Value
}

function Get-PrivilegedGroupDefinitions {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Domain,[Parameter(Mandatory)]$Forest)
    $definitions = [System.Collections.Generic.List[object]]::new()
    $rootDomainParameters = Get-AdCommandParameters
    $rootDomain = Get-ADDomain -Identity $Forest.RootDomain @rootDomainParameters
    $rootSid = Get-ObjectSidString $rootDomain.DomainSID
    $domainGroups = @(
        @{ Rid=512; Name='Domain Admins'; Type='Domain' }, @{ Rid=518; Name='Schema Admins'; Type='Forest' },
        @{ Rid=519; Name='Enterprise Admins'; Type='Forest' }, @{ Rid=520; Name='Group Policy Creator Owners'; Type='Domain' },
        @{ Rid=526; Name='Key Admins'; Type='Domain' }, @{ Rid=527; Name='Enterprise Key Admins'; Type='Forest' },
        @{ Rid=110; Name='DNSAdmins'; Type='Domain' }
    )
    foreach ($domain in @($Domain)) {
        $domainSid = Get-ObjectSidString $domain.DomainSID
        foreach ($item in $domainGroups) {
            # Forest-wide groups exist only in the forest root; domain-specific groups are evaluated in every domain.
            if ($item.Type -eq 'Forest' -and $domain.DNSRoot -ne $Forest.RootDomain) { continue }
            $sidPrefix = if ($item.Type -eq 'Forest') { $rootSid } else { $domainSid }
            $definitions.Add([pscustomobject]@{ SID="$sidPrefix-$($item.Rid)"; GroupName=$item.Name; PrivilegeType=$item.Type; Source='Well-known security group'; Domain=$domain.DNSRoot })
        }
    }
    $builtin = @(
        @{ Rid=544; Name='Administrators' }, @{ Rid=548; Name='Account Operators' }, @{ Rid=549; Name='Server Operators' },
        @{ Rid=550; Name='Print Operators' }, @{ Rid=551; Name='Backup Operators' }, @{ Rid=552; Name='Replicator' },
        @{ Rid=553; Name='RAS and IAS Servers' }, @{ Rid=556; Name='Network Configuration Operators' },
        @{ Rid=557; Name='Incoming Forest Trust Builders' }, @{ Rid=562; Name='Distributed COM Users' }, @{ Rid=569; Name='Cryptographic Operators' }
    )
    foreach ($item in $builtin) { $definitions.Add([pscustomobject]@{ SID="S-1-5-32-$($item.Rid)"; GroupName=$item.Name; PrivilegeType='Domain'; Source='Built-in security group' }) }
    return $definitions
}

function Get-DirectoryInventory {
    [CmdletBinding()]
    param()
    $common = Get-AdCommandParameters
    Write-Progress -Activity 'Active Directory privilege audit' -Status 'Reading AD users, groups and computers' -PercentComplete 5
    $forest = Get-ADForest @common
    $domains = @(); $users = @(); $groups = @(); $computers = @()
    foreach ($domainName in $forest.Domains) {
        $domainParameters = @{ Server=$domainName; ErrorAction='Stop' }; if ($script:Credential) { $domainParameters.Credential = $script:Credential }
        try {
            Write-Verbose "Reading directory objects from $domainName"
            $domains += Get-ADDomain @domainParameters
            $users += @(Get-ADUser -LDAPFilter '(&(objectCategory=person)(objectClass=user))' -Properties DisplayName,Enabled,UserPrincipalName,ServicePrincipalName,adminCount,PasswordLastSet,LastLogonDate,SID @domainParameters)
            $groups += @(Get-ADGroup -LDAPFilter '(objectCategory=group)' -Properties member,adminCount,GroupCategory,GroupScope,SID,Description @domainParameters)
            $computers += @(Get-ADComputer -LDAPFilter '(&(objectCategory=computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))' -Properties DNSHostName,Enabled,OperatingSystem,SID @domainParameters)
        } catch { Add-AuditError -Stage 'Forest domain inventory' -Computer $domainName -Exception $_.Exception }
    }
    return [pscustomobject]@{ Users=$users; Groups=$groups; Computers=$computers; Domain=$domains; Forest=$forest }
}

function New-DirectoryCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Inventory)
    $byDn = @{}; $bySid = @{}; $bySam = @{}
    foreach ($object in @($Inventory.Users) + @($Inventory.Groups) + @($Inventory.Computers)) {
        $sid = Get-ObjectSidString $object.SID
        $entry = [pscustomobject]@{ DistinguishedName=$object.DistinguishedName; Name=$object.Name; SamAccountName=$object.SamAccountName; ObjectClass=([string]$object.ObjectClass); SID=$sid; DisplayName=$object.DisplayName; Enabled=$object.Enabled; UserPrincipalName=$object.UserPrincipalName; ServicePrincipalName=$object.ServicePrincipalName; AdminCount=$object.adminCount; Members=@($object.member); Description=$object.Description }
        $byDn[$entry.DistinguishedName] = $entry
        if ($sid) { $bySid[$sid] = $entry }
        if ($entry.SamAccountName) { $bySam[$entry.SamAccountName.ToLowerInvariant()] = $entry }
    }
    return [pscustomobject]@{ ByDn=$byDn; BySid=$bySid; BySam=$bySam }
}

function Resolve-DirectoryObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DistinguishedName,[Parameter(Mandatory)]$Cache)
    if ($Cache.ByDn.ContainsKey($DistinguishedName)) { return $Cache.ByDn[$DistinguishedName] }
    try {
        $objectParameters = Get-AdCommandParameters
        $object = Get-ADObject -Identity $DistinguishedName -Properties objectSid,objectClass,name,sAMAccountName,displayName,userPrincipalName,adminCount,member,servicePrincipalName,enabled @objectParameters
        $entry = [pscustomobject]@{ DistinguishedName=$object.DistinguishedName; Name=$object.Name; SamAccountName=$object.sAMAccountName; ObjectClass=([string]$object.ObjectClass); SID=(Get-ObjectSidString $object.objectSid); DisplayName=$object.displayName; Enabled=$object.enabled; UserPrincipalName=$object.userPrincipalName; ServicePrincipalName=$object.servicePrincipalName; AdminCount=$object.adminCount; Members=@($object.member); Description=$null }
        $Cache.ByDn[$entry.DistinguishedName] = $entry; if ($entry.SID) { $Cache.BySid[$entry.SID] = $entry }; return $entry
    } catch { return [pscustomobject]@{ DistinguishedName=$DistinguishedName; Name=$DistinguishedName; SamAccountName=$null; ObjectClass='unknown'; SID=$null; DisplayName=$null; Enabled=$null; UserPrincipalName=$null; ServicePrincipalName=$null; AdminCount=$null; Members=@(); Description=$null } }
}

function Get-GroupMembershipPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RootGroup,
        [Parameter(Mandatory)]$Cache,
        [Parameter(Mandatory)][string]$PrivilegeType,
        [string]$Computer = 'DOMAIN'
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue([pscustomobject]@{ Group=$RootGroup; Path=@($RootGroup.DistinguishedName); GroupPath=@($RootGroup.Name); InheritedVia='Direct' })
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        foreach ($memberDn in @($node.Group.Members)) {
            $member = Resolve-DirectoryObject -DistinguishedName $memberDn -Cache $Cache
            $path = @($node.Path + $member.DistinguishedName); $names = @($node.GroupPath + $member.Name)
            if ($member.ObjectClass -eq 'group') {
                if ($node.Path -contains $member.DistinguishedName) {
                    $results.Add([pscustomobject]@{ User=''; DisplayName=''; Enabled=''; SID=$member.SID; DistinguishedName=$member.DistinguishedName; UserPrincipalName=''; Computer=$Computer; PrivilegeType=$PrivilegeType; PrivilegedGroup=$RootGroup.Name; GrantedThrough=$node.Group.Name; DirectOrInherited='Broken group nesting (cycle)'; InheritedVia=($names -join ' -> '); InheritancePath=($names -join ' -> '); ObjectType='Group cycle'; ServiceAccount=$false; Finding='Circular nested group membership' }); continue
                }
                $queue.Enqueue([pscustomobject]@{ Group=$member; Path=$path; GroupPath=$names; InheritedVia='Inherited' }); continue
            }
            $direct = if ($node.Group.DistinguishedName -eq $RootGroup.DistinguishedName) { 'Direct' } else { 'Inherited' }
            $isService = ($member.ObjectClass -eq 'user' -and @($member.ServicePrincipalName).Count -gt 0)
            $results.Add([pscustomobject]@{ User=$member.SamAccountName; DisplayName=$member.DisplayName; Enabled=$member.Enabled; SID=$member.SID; DistinguishedName=$member.DistinguishedName; UserPrincipalName=$member.UserPrincipalName; Computer=$Computer; PrivilegeType=$PrivilegeType; PrivilegedGroup=$RootGroup.Name; GrantedThrough=$node.Group.Name; DirectOrInherited=$direct; InheritedVia=($names -join ' -> '); InheritancePath=($names -join ' -> '); ObjectType=$member.ObjectClass; ServiceAccount=$isService; Finding=$(if ($member.ObjectClass -eq 'unknown') {'Unknown or orphaned directory object'} else {''}) })
        }
    }
    return $results
}

function Get-PrivilegedDirectoryGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Inventory,[Parameter(Mandatory)]$Cache)
    $definitions = Get-PrivilegedGroupDefinitions -Domain $Inventory.Domain -Forest $Inventory.Forest
    $selected = @{}
    foreach ($definition in $definitions) {
        foreach ($candidate in $Inventory.Groups | Where-Object { (Get-ObjectSidString $_.SID) -eq $definition.SID }) {
            $selected[$candidate.DistinguishedName] = [pscustomobject]@{ Group=$Cache.ByDn[$candidate.DistinguishedName]; Definition=$definition }
        }
    }
    foreach ($group in $Inventory.Groups | Where-Object { $_.adminCount -eq 1 }) {
        $sid = Get-ObjectSidString $group.SID
        if (-not $selected.ContainsKey($group.DistinguishedName)) { $selected[$group.DistinguishedName] = [pscustomobject]@{ Group=$Cache.ByDn[$group.DistinguishedName]; Definition=[pscustomobject]@{ SID=$sid; GroupName=$group.Name; PrivilegeType='Domain'; Source='adminCount=1 protected group' } } }
    }
    return @($selected.Values | Sort-Object { $_.Group.Name })
}

function Get-RemoteLocalAdministrators {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Computers,[int]$MaximumConcurrency,[System.Management.Automation.PSCredential]$RemoteCredential)
    $worker = {
        param($ComputerName,$CredentialObject)
        $session = $null
        try {
            $option = New-CimSessionOption -Protocol Dcom
            $args = @{ ComputerName=$ComputerName; SessionOption=$option; ErrorAction='Stop' }
            if ($CredentialObject) { $args.Credential = $CredentialObject }
            $session = New-CimSession @args
            $group = Get-CimInstance -CimSession $session -ClassName Win32_Group -Filter "LocalAccount=TRUE AND SID='S-1-5-32-544'" -ErrorAction Stop
            if (-not $group) { return [pscustomobject]@{ RecordType='Error'; Computer=$ComputerName; Category='WMI/CIM failure'; Message='Local Administrators group was not returned.' } }
            foreach ($member in @(Get-CimAssociatedInstance -CimSession $session -InputObject $group -Association Win32_GroupUser -ErrorAction Stop)) {
                [pscustomobject]@{ RecordType='Member'; Computer=$ComputerName; MemberDomain=[string]$member.Domain; MemberName=[string]$member.Name; MemberSID=[string]$member.SID; MemberClass=[string]$member.CimClass.CimClassName; Protocol='DCOM/WMI' }
            }
        } catch {
            $message = $_.Exception.Message
            $category = if ($message -match '(?i)access is denied|unauthorized') {'Access denied'} elseif ($message -match '(?i)rpc server|network path|not found|unavailable|timed out|0x800706ba') {'Offline or WMI unavailable'} else {'WMI/CIM failure'}
            [pscustomobject]@{ RecordType='Error'; Computer=$ComputerName; Category=$category; Message=$message }
        } finally { if ($session) { $session | Remove-CimSession -ErrorAction SilentlyContinue } }
    }
    $pool = [runspacefactory]::CreateRunspacePool(1,$MaximumConcurrency); $pool.Open(); $jobs = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($computer in $Computers) {
            $name = if ($computer.DNSHostName) { $computer.DNSHostName } else { $computer.Name }
            $ps = [powershell]::Create(); $ps.RunspacePool = $pool; $null = $ps.AddScript($worker).AddArgument($name).AddArgument($RemoteCredential)
            $jobs.Add([pscustomobject]@{ Computer=$name; PowerShell=$ps; Handle=$ps.BeginInvoke() })
        }
        $output = [System.Collections.Generic.List[object]]::new(); $completed = 0
        foreach ($job in $jobs) {
            try { foreach ($record in @($job.PowerShell.EndInvoke($job.Handle))) { $output.Add($record) } } catch { $output.Add([pscustomobject]@{ RecordType='Error'; Computer=$job.Computer; Category='WMI/CIM failure'; Message=$_.Exception.Message }) } finally { $job.PowerShell.Dispose() }
            $completed++; Write-Progress -Activity 'Local Administrators inventory' -Status "$completed of $($jobs.Count) computers" -PercentComplete (($completed / [math]::Max($jobs.Count,1))*100)
        }
        return $output
    } finally { $pool.Close(); $pool.Dispose(); Write-Progress -Activity 'Local Administrators inventory' -Completed }
}

function Convert-LocalAdministratorRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$RemoteRecords,[Parameter(Mandatory)]$Cache)
    $effective = [System.Collections.Generic.List[object]]::new(); $localMembers = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $RemoteRecords) {
        if ($record.RecordType -eq 'Error') { continue }
        $resolved = $null
        if ($record.MemberSID -and $Cache.BySid.ContainsKey($record.MemberSID)) { $resolved = $Cache.BySid[$record.MemberSID] }
        elseif ($record.MemberName -and $Cache.BySam.ContainsKey($record.MemberName.ToLowerInvariant())) { $resolved = $Cache.BySam[$record.MemberName.ToLowerInvariant()] }
        $localMembers.Add([pscustomobject]@{ Computer=$record.Computer; Member="$($record.MemberDomain)\$($record.MemberName)"; MemberSID=$record.MemberSID; MemberClass=$record.MemberClass; Resolved=($null -ne $resolved); Protocol=$record.Protocol })
        if ($resolved -and $resolved.ObjectClass -eq 'group') {
            foreach ($path in Get-GroupMembershipPaths -RootGroup $resolved -Cache $Cache -PrivilegeType 'Local' -Computer $record.Computer) { $path.PrivilegedGroup = 'Local Administrators'; $path.GrantedThrough = $resolved.Name; $effective.Add($path) }
        } elseif ($resolved) {
            $isService = ($resolved.ObjectClass -eq 'user' -and @($resolved.ServicePrincipalName).Count -gt 0)
            $effective.Add([pscustomobject]@{ User=$resolved.SamAccountName; DisplayName=$resolved.DisplayName; Enabled=$resolved.Enabled; SID=$resolved.SID; DistinguishedName=$resolved.DistinguishedName; UserPrincipalName=$resolved.UserPrincipalName; Computer=$record.Computer; PrivilegeType='Local'; PrivilegedGroup='Local Administrators'; GrantedThrough="$($record.MemberDomain)\$($record.MemberName)"; DirectOrInherited='Direct'; InheritedVia="$($record.MemberDomain)\$($record.MemberName)"; InheritancePath="$($record.MemberDomain)\$($record.MemberName)"; ObjectType=$resolved.ObjectClass; ServiceAccount=$isService; Finding='' })
        } else {
            $finding = if ($record.MemberSID -match '^S-1-5-21-') {'Unknown or orphaned SID'} else {''}
            $effective.Add([pscustomobject]@{ User=$record.MemberName; DisplayName=''; Enabled=''; SID=$record.MemberSID; DistinguishedName=''; UserPrincipalName=''; Computer=$record.Computer; PrivilegeType='Local'; PrivilegedGroup='Local Administrators'; GrantedThrough="$($record.MemberDomain)\$($record.MemberName)"; DirectOrInherited='Direct'; InheritedVia="$($record.MemberDomain)\$($record.MemberName)"; InheritancePath="$($record.MemberDomain)\$($record.MemberName)"; ObjectType=$record.MemberClass; ServiceAccount=$false; Finding=$finding })
        }
    }
    return [pscustomobject]@{ Effective=$effective; LocalMembers=$localMembers }
}

function Get-SecurityFindings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Effective,[Parameter(Mandatory)][object[]]$LocalMembers,[Parameter(Mandatory)]$Inventory)
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Effective) {
        if ($item.Enabled -eq $false) { $findings.Add([pscustomobject]@{ Severity='High'; Category='Disabled account with administrative rights'; User=$item.User; Computer=$item.Computer; Detail=$item.InheritancePath }) }
        if ($item.Finding) { $findings.Add([pscustomobject]@{ Severity='High'; Category=$item.Finding; User=$item.User; Computer=$item.Computer; Detail=$item.InheritancePath }) }
    }
    foreach ($member in $LocalMembers | Where-Object { $_.Member -match '(?i)\\(Domain Users|Everyone|Authenticated Users)$' }) { $findings.Add([pscustomobject]@{ Severity='Critical'; Category='Broad principal in Local Administrators'; User=$member.Member; Computer=$member.Computer; Detail='Remove or justify broad local administration assignment.' }) }
    foreach ($group in $Inventory.Groups | Where-Object { $_.adminCount -eq 1 -and @($_.member).Count -eq 0 }) { $findings.Add([pscustomobject]@{ Severity='Medium'; Category='Empty protected group'; User=$group.Name; Computer='DOMAIN'; Detail='adminCount=1 group has no direct members.' }) }
    $effectiveGroups = $Effective | Group-Object SID,Computer,PrivilegeType | Where-Object { $_.Count -gt 1 }
    foreach ($duplicate in $effectiveGroups) { $sample = $duplicate.Group[0]; $findings.Add([pscustomobject]@{ Severity='Medium'; Category='Duplicate privilege paths'; User=$sample.User; Computer=$sample.Computer; Detail="$($duplicate.Count) paths grant $($sample.PrivilegeType) administration." }) }
    # FIX (v1.0.1): wrap the Select-Object -Unique result in @() so .Count is always valid.
    # Without this, a user with exactly one unique PrivilegedGroup value causes Select-Object -Unique
    # to return a bare string instead of an array. Under Set-StrictMode -Version Latest on
    # Windows PowerShell 5.1, a string has no .Count member and this throws a fatal error.
    # (PowerShell 7+ tolerates this via its intrinsic scalar .Count property, but the @() wrap
    # is version-independent and costs nothing, so it's applied regardless of host version.)
    foreach ($multi in ($Effective | Where-Object { $_.User } | Group-Object User | Where-Object { @($_.Group.PrivilegedGroup | Select-Object -Unique).Count -gt 1 })) { $findings.Add([pscustomobject]@{ Severity='Medium'; Category='Multiple administrative grants'; User=$multi.Name; Computer='Multiple'; Detail=(($multi.Group.PrivilegedGroup | Select-Object -Unique) -join '; ') }) }
    return $findings
}

function Export-CsvReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[AllowNull()][object[]]$Data)
    $path = Join-Path $script:AuditDirectory "$Name`_$($script:RunStamp).csv"
    @($Data) | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Export-ExcelReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Sheets,[Parameter(Mandatory)][object[]]$Summary)
    $path = Join-Path $script:AuditDirectory "AD_Privilege_Audit_$($script:RunStamp).xlsx"
    $Summary | Export-Excel -Path $path -WorksheetName 'Executive Summary' -TableName 'ExecutiveSummary' -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
    foreach ($sheetName in $Sheets.Keys) {
        $tableName = ($sheetName -replace '[^A-Za-z0-9]','') + 'Table'
        @($Sheets[$sheetName]) | Export-Excel -Path $path -WorksheetName $sheetName -TableName $tableName -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -Append
    }
    $package = Open-ExcelPackage -Path $path
    foreach ($worksheet in $package.Workbook.Worksheets) {
        if ($worksheet.Dimension) { $worksheet.Cells[$worksheet.Dimension.Address].Style.VerticalAlignment = 'Top'; $worksheet.Cells[$worksheet.Dimension.Address].AutoFitColumns() }
        if ($worksheet.Name -in @('Findings','Disabled Admin Accounts','Errors','Offline Computers')) { Add-ConditionalFormatting -Worksheet $worksheet -Address "A2:A$($worksheet.Dimension.End.Row)" -RuleType ContainsText -ConditionValue 'Critical' -BackgroundColor 'Red' -ForegroundColor 'White' }
    }
    $summarySheet = $package.Workbook.Worksheets['Executive Summary']
    if ($summarySheet.Dimension.End.Row -gt 2) { Add-ExcelChart -ExcelPackage $package -WorksheetName 'Executive Summary' -ChartType ColumnClustered -XRange 'A2:A10' -YRange 'B2:B10' -Title 'Administrative Privilege Summary' -TopRow 2 -LeftColumn 4 -Width 550 -Height 330 }
    Close-ExcelPackage -ExcelPackage $package
    return $path
}

function Invoke-ADPrivilegeAudit {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*$')]
        [string]$DomainController,
        [System.Management.Automation.PSCredential]$Credential,
        [switch]$SkipLocalAdministratorScan,
        [switch]$InstallImportExcel,
        [ValidateRange(1,128)]
        [int]$ThrottleLimit = 24
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Helper functions are loaded into toolkit script scope, so keep command configuration there.
    $script:DomainController = $DomainController
    $script:Credential = $Credential
    $script:SkipLocalAdministratorScan = $SkipLocalAdministratorScan
    $script:InstallImportExcel = $InstallImportExcel
    $script:ThrottleLimit = $ThrottleLimit

    $script:Version = '1.0.1'
    $script:StartedAt = Get-Date
    $script:ScriptDirectory = $PSScriptRoot
    $script:AuditDirectory = Join-Path -Path $script:ScriptDirectory -ChildPath 'AD_Audit'
    $script:LogDirectory = Join-Path -Path $script:ScriptDirectory -ChildPath 'Logs'
    $script:RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogPath = Join-Path -Path $script:LogDirectory -ChildPath "Audit-ADPrivileges_$($script:RunStamp).log"
    $script:Errors = [System.Collections.Generic.List[object]]::new()
    $script:Warnings = [System.Collections.Generic.List[object]]::new()

    try {
        Initialize-AuditDirectories
    Write-AuditLog -Level Information -Message "Audit-ADPrivileges $script:Version started."
    Import-RequiredModules
    $inventory = Get-DirectoryInventory; $cache = New-DirectoryCache -Inventory $inventory
    $privilegedGroups = Get-PrivilegedDirectoryGroups -Inventory $inventory -Cache $cache
    $adEffective = [System.Collections.Generic.List[object]]::new(); $index = 0
    foreach ($selection in $privilegedGroups) {
        $index++; Write-Progress -Activity 'Enumerating privileged AD groups' -Status $selection.Group.Name -PercentComplete (($index/[math]::Max($privilegedGroups.Count,1))*100)
        try { foreach ($entry in Get-GroupMembershipPaths -RootGroup $selection.Group -Cache $cache -PrivilegeType $selection.Definition.PrivilegeType) { $adEffective.Add($entry) } } catch { Add-AuditError -Stage 'Nested group enumeration' -Computer 'DOMAIN' -Exception $_.Exception }
    }
    Write-Progress -Activity 'Enumerating privileged AD groups' -Completed
    $remoteRecords = @(); $localResult = [pscustomobject]@{ Effective=@(); LocalMembers=@() }
    if (-not $script:SkipLocalAdministratorScan) {
        Write-AuditLog -Level Information -Message "Starting parallel local Administrators inventory for $($inventory.Computers.Count) enabled domain computer accounts."
        $remoteRecords = @(Get-RemoteLocalAdministrators -Computers $inventory.Computers -MaximumConcurrency $script:ThrottleLimit -RemoteCredential $script:Credential)
        foreach ($failure in $remoteRecords | Where-Object { $_.RecordType -eq 'Error' }) { $script:Errors.Add([pscustomobject]@{ Time=Get-Date; Stage='Local Administrators inventory'; Computer=$failure.Computer; Category=$failure.Category; Message=$failure.Message }); Write-AuditLog -Level Warning -ComputerName $failure.Computer -Message "$($failure.Category): $($failure.Message)" }
        $localResult = Convert-LocalAdministratorRecords -RemoteRecords $remoteRecords -Cache $cache
    }
    $effective = @($adEffective) + @($localResult.Effective)
    $findings = Get-SecurityFindings -Effective $effective -LocalMembers @($localResult.LocalMembers) -Inventory $inventory
    $staleAdminCount = @($inventory.Users | Where-Object { $_.adminCount -eq 1 -and $_.DistinguishedName -notin $effective.DistinguishedName } | ForEach-Object { [pscustomobject]@{ User=$_.SamAccountName; DisplayName=$_.DisplayName; Enabled=$_.Enabled; SID=(Get-ObjectSidString $_.SID); DistinguishedName=$_.DistinguishedName; Reason='adminCount=1 but no effective privilege path was found in enumerated groups; review before clearing.' } })
    $sheets = [ordered]@{
        'Domain Admins'=@($effective | Where-Object { $_.PrivilegedGroup -eq 'Domain Admins' }); 'Enterprise Admins'=@($effective | Where-Object { $_.PrivilegedGroup -eq 'Enterprise Admins' }); 'Schema Admins'=@($effective | Where-Object { $_.PrivilegedGroup -eq 'Schema Admins' });
        'Privileged Groups'=@($privilegedGroups | ForEach-Object { [pscustomobject]@{ Group=$_.Group.Name; SID=$_.Group.SID; DistinguishedName=$_.Group.DistinguishedName; PrivilegeType=$_.Definition.PrivilegeType; Source=$_.Definition.Source; DirectMembers=@($_.Group.Members).Count; AdminCount=$_.Group.AdminCount } });
        'Local Administrators'=@($localResult.LocalMembers); 'Effective Privileges'=@($effective); 'Disabled Admin Accounts'=@($effective | Where-Object { $_.Enabled -eq $false }); 'Service Accounts'=@($effective | Where-Object { $_.ServiceAccount }); 'Stale adminCount'=$staleAdminCount;
        'Duplicate Privileges'=@($effective | Group-Object SID,Computer,PrivilegeType | Where-Object Count -gt 1 | ForEach-Object { $_.Group }); 'Findings'=@($findings); 'Errors'=@($script:Errors); 'Offline Computers'=@($remoteRecords | Where-Object { $_.RecordType -eq 'Error' -and $_.Category -eq 'Offline or WMI unavailable' })
    }
    foreach ($name in $sheets.Keys) { $null = Export-CsvReport -Name ($name -replace ' ','_') -Data @($sheets[$name]) }
    $summary = @(
        [pscustomobject]@{ Metric='Audit version'; Value=$script:Version }, [pscustomobject]@{ Metric='Start time'; Value=$script:StartedAt }, [pscustomobject]@{ Metric='End time'; Value=(Get-Date) },
        [pscustomobject]@{ Metric='AD users queried'; Value=$inventory.Users.Count }, [pscustomobject]@{ Metric='AD computers queried'; Value=$inventory.Computers.Count }, [pscustomobject]@{ Metric='Privileged AD groups'; Value=$privilegedGroups.Count },
        [pscustomobject]@{ Metric='Effective privilege paths'; Value=$effective.Count }, [pscustomobject]@{ Metric='Critical findings'; Value=@($findings | Where-Object Severity -eq 'Critical').Count }, [pscustomobject]@{ Metric='High findings'; Value=@($findings | Where-Object Severity -eq 'High').Count },
        [pscustomobject]@{ Metric='Errors or unavailable computers'; Value=$script:Errors.Count }
    )
    $excelCreated = $false; if (Import-ExcelModule -AttemptInstall:$script:InstallImportExcel) { try { $excelPath = Export-ExcelReport -Sheets $sheets -Summary $summary; $excelCreated = $true; Write-AuditLog -Level Information -Message "Excel workbook created: $excelPath" } catch { Add-AuditError -Stage 'Excel export' -Computer '' -Exception $_.Exception } }
    $duration = (Get-Date) - $script:StartedAt; Write-AuditLog -Level Information -Message "Audit completed in $($duration.ToString()). CSV output: $script:AuditDirectory. Excel created: $excelCreated."
    return [pscustomobject]@{ OutputDirectory=$script:AuditDirectory; LogPath=$script:LogPath; ExcelCreated=$excelCreated; Duration=$duration; Findings=$findings.Count; Errors=$script:Errors.Count }
    }
    catch {
        if (Test-Path -LiteralPath $script:LogDirectory) {
            Add-AuditError -Stage 'Fatal audit failure' -Computer '' -Exception $_.Exception
        }
        throw
    }
    finally {
        Write-Progress -Activity 'Active Directory privilege audit' -Completed
    }
}