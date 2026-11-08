#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$setupUIPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SetupUI.wxs'
if (!(Test-Path -LiteralPath $setupUIPath)) { throw "SetupUI.wxs not found at $setupUIPath" }

[xml]$xml = Get-Content -LiteralPath $setupUIPath -Raw -Encoding UTF8

$serverComplete = $xml.Wix.Fragment.UI.Dialog | Where-Object { $_.Id -eq 'ServerComplete' }
if ($null -eq $serverComplete) { throw 'ServerComplete dialog not found in SetupUI.wxs.' }

$openControl = $serverComplete.Control | Where-Object { $_.Id -eq 'Open' }
if ($null -eq $openControl) { throw 'Open control not found in ServerComplete dialog.' }
$hideCondition = $openControl.HideCondition
if ([string]::IsNullOrWhiteSpace($hideCondition)) { throw 'Open control missing HideCondition.' }

$finishControl = $serverComplete.Control | Where-Object { $_.Id -eq 'Finish' }
if ($null -eq $finishControl) { throw 'Finish control not found in ServerComplete dialog.' }
$publishAction = $finishControl.Publish | Where-Object { $_.Event -eq 'DoAction' -and $_.Value -eq 'OpenSyntaur' }
if ($null -eq $publishAction) { throw 'DoAction OpenSyntaur publish event not found.' }
$actionCondition = $publishAction.Condition
if ([string]::IsNullOrWhiteSpace($actionCondition)) { throw 'DoAction OpenSyntaur missing Condition.' }

function Evaluate-MsiCondition {
    param(
        [string]$ConditionText,
        [hashtable]$Properties
    )
    $evalText = $ConditionText
    $evalText = [regex]::Replace($evalText, 'REMOVE~="ALL"', {
        param($m)
        if ($Properties.ContainsKey('REMOVE') -and ($Properties['REMOVE'] -ne $null) -and ($Properties['REMOVE'].ToString().ToUpperInvariant() -eq 'ALL')) { '($true)' } else { '($false)' }
    })
    $evalText = [regex]::Replace($evalText, 'OPEN_SYNTAUR\s*=\s*"1"', {
        param($m)
        if ($Properties.ContainsKey('OPEN_SYNTAUR') -and ($Properties['OPEN_SYNTAUR'] -eq '1')) { '($true)' } else { '($false)' }
    })
    $evalText = [regex]::Replace($evalText, '\bInstalled\b', {
        param($m)
        if ($Properties.ContainsKey('Installed') -and [bool]$Properties['Installed']) { '($true)' } else { '($false)' }
    })
    $evalText = [regex]::Replace($evalText, '\bWIX_UPGRADE_DETECTED\b', {
        param($m)
        if ($Properties.ContainsKey('WIX_UPGRADE_DETECTED') -and [bool]$Properties['WIX_UPGRADE_DETECTED']) { '($true)' } else { '($false)' }
    })
    $evalText = [regex]::Replace($evalText, '\bAND\b', '-and')
    $evalText = [regex]::Replace($evalText, '\bOR\b', '-or')
    $evalText = [regex]::Replace($evalText, '\bNOT\b', '-not')

    return Invoke-Expression $evalText
}

function Test-Scenario {
    param(
        [string]$Name,
        [hashtable]$Props,
        [bool]$ExpectCheckboxVisible,
        [bool]$ExpectActionFired
    )
    $hidden = Evaluate-MsiCondition -ConditionText $hideCondition -Properties $Props
    $checkboxVisible = -not $hidden
    $actionFired = Evaluate-MsiCondition -ConditionText $actionCondition -Properties $Props

    if ($checkboxVisible -ne $ExpectCheckboxVisible) {
        throw "Scenario '$Name': Expected CheckboxVisible=$ExpectCheckboxVisible, got $checkboxVisible"
    }
    if ($actionFired -ne $ExpectActionFired) {
        throw "Scenario '$Name': Expected ActionFired=$ExpectActionFired, got $actionFired"
    }
    Write-Output "PASS: $Name"
}

Test-Scenario 'Fresh Install (default OPEN_SYNTAUR=1)' @{ OPEN_SYNTAUR = '1'; Installed = $false; WIX_UPGRADE_DETECTED = $false; REMOVE = '' } $true $true
Test-Scenario 'Major Upgrade (default OPEN_SYNTAUR=1)' @{ OPEN_SYNTAUR = '1'; Installed = $false; WIX_UPGRADE_DETECTED = $true; REMOVE = '' } $true $true
Test-Scenario 'Major Upgrade Opt-Out (OPEN_SYNTAUR=0)' @{ OPEN_SYNTAUR = '0'; Installed = $false; WIX_UPGRADE_DETECTED = $true; REMOVE = '' } $true $false
Test-Scenario 'Fresh Install Opt-Out (OPEN_SYNTAUR=0)' @{ OPEN_SYNTAUR = '0'; Installed = $false; WIX_UPGRADE_DETECTED = $false; REMOVE = '' } $true $false
Test-Scenario 'Maintenance Repair (Installed)' @{ OPEN_SYNTAUR = '1'; Installed = $true; WIX_UPGRADE_DETECTED = $false; REMOVE = '' } $false $false
Test-Scenario 'Removal (REMOVE=ALL)' @{ OPEN_SYNTAUR = '1'; Installed = $false; WIX_UPGRADE_DETECTED = $false; REMOVE = 'ALL' } $false $false

Write-Output 'All SetupUI upgrade and maintenance condition fixture checks passed.'
