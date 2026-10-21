# Demo.ps1 - shows the Steps.ps1 checklist.   Run: .\Demo.ps1   (or: .\Demo.ps1 -Fail)
param([switch]$Fail)
. "$PSScriptRoot\Steps.ps1"

Start-StepList -Title 'Demo setup' -Steps @(
    'Detect PowerShell version'
    'Download things'
    'Configure things'
    'Optional extra'
    'Final check'
)

Invoke-Step 1 {
    $script:PsVersion = $PSVersionTable.PSVersion.ToString()   # $script: keeps it for later steps
    "Running on PowerShell $script:PsVersion"
}
Invoke-Step 2 { 1..3 | ForEach-Object { "working... $_"; Start-Sleep -Seconds 1 } }
if ($Fail) {
    Invoke-Step 3 {
        'about to fail'
        Get-Item 'C:\does\not\exist'   # any error fails the step
        'never printed'
    }
} else {
    Invoke-Step 3 { Invoke-NativeCommand git --version; Start-Sleep -Seconds 1 }
}
Skip-Step 4 "not needed on PowerShell $PsVersion"
Invoke-Step 5 { Start-Sleep -Seconds 1 }
$null = Complete-StepList
