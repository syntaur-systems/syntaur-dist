$ErrorActionPreference = "Stop"

$Repository = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Temporary = Join-Path ([IO.Path]::GetTempPath()) ("syntaur-eula-test-" + [Guid]::NewGuid().ToString("N"))
$OriginalUserProfile = $env:USERPROFILE
$OriginalLibraryOnly = $env:SYNTAUR_INSTALL_TEST_LIBRARY_ONLY

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-LegacyRecord {
    param([string]$Record)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Record) | Out-Null
    [IO.File]::WriteAllLines(
        $Record,
        @(
            "eula_version=1.0",
            "eula_url=https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md",
            "accepted_at=2026-07-17T13:58:33Z",
            "method=flag",
            "installer_version=0.7.114"
        ),
        (New-Object -TypeName System.Text.UnicodeEncoding -ArgumentList @($false, $true))
    )
}

function Add-EveryoneWriteRule {
    param([string]$LiteralPath)
    $Acl = Get-Acl -LiteralPath $LiteralPath
    $Everyone = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList @("S-1-1-0")
    $Rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $Everyone,
        [Security.AccessControl.FileSystemRights]::Write,
        [Security.AccessControl.AccessControlType]::Allow
    )
    [void]$Acl.AddAccessRule($Rule)
    Set-Acl -LiteralPath $LiteralPath -AclObject $Acl
}

function Restore-Sddl {
    param([string]$LiteralPath, [string]$Sddl)
    $Acl = Get-Acl -LiteralPath $LiteralPath
    $Acl.SetSecurityDescriptorSddlForm($Sddl)
    Set-Acl -LiteralPath $LiteralPath -AclObject $Acl
}

function Protect-TestDirectory {
    param([string]$LiteralPath)
    $Acl = New-Object -TypeName System.Security.AccessControl.DirectorySecurity
    $CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $Acl.SetOwner($CurrentSid)
    foreach ($SidValue in @($CurrentSid.Value, "S-1-5-18", "S-1-5-32-544")) {
        $Sid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList @($SidValue)
        $Rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $Sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$Acl.AddAccessRule($Rule)
    }
    $Acl.SetAccessRuleProtection($true, $false)
    Set-Acl -LiteralPath $LiteralPath -AclObject $Acl
}

try {
    New-Item -ItemType Directory -Path $Temporary | Out-Null
    Protect-TestDirectory -LiteralPath $Temporary
    $ExpectedHash = "3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720"
    $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Repository "EULA.md")).Hash.ToLowerInvariant()
    Assert-True ($ActualHash -eq $ExpectedHash) "EULA hash drifted"

    $env:SYNTAUR_INSTALL_TEST_LIBRARY_ONLY = "1"
    . (Join-Path $Repository "install.ps1")
    Assert-True ($EulaSha256 -eq $ExpectedHash) "installer EULA hash is stale"

    $env:USERPROFILE = Join-Path $Temporary "legacy"
    $Legacy = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    Write-LegacyRecord -Record $Legacy
    $Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $Legacy).Hash
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Legacy)) "hashless legacy record was accepted"
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $true) "legacy record was not upgraded"
    $After = (Get-FileHash -Algorithm SHA256 -LiteralPath $Legacy).Hash
    Assert-True ($Before -ne $After) "legacy record was not replaced with hash-bound evidence"
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Legacy) "upgraded record was rejected"

    $env:USERPROFILE = Join-Path $Temporary "current"
    New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
    Assert-True (Save-EulaAcceptance -Method "prompt") "current record was not stored"
    $Current = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Current) "current record was rejected"
    $BeforeCurrentReuse = (Get-FileHash -Algorithm SHA256 -LiteralPath $Current).Hash
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $false) "current record was not reused"
    $AfterCurrentReuse = (Get-FileHash -Algorithm SHA256 -LiteralPath $Current).Hash
    Assert-True ($BeforeCurrentReuse -eq $AfterCurrentReuse) "current reuse rewrote its evidence"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Current) -Filter ".eula-accepted.tmp.*")
    Assert-True ($Residue.Count -eq 0) "atomic record write left temporary files"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Current) -Filter ".eula-accepted.backup.*")
    Assert-True ($Residue.Count -eq 0) "atomic record replacement left backup files"

    $BadLines = [IO.File]::ReadAllLines($Current)
    $BadLines[2] = "eula_sha256=" + ("a" * 64)
    [IO.File]::WriteAllLines($Current, $BadLines)
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "wrong EULA hash was accepted"
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $true) "flag acceptance did not repair mismatch"
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Current) "repaired record was rejected"

    [IO.File]::AppendAllText($Current, "method=flag`r`n")
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "duplicate field was accepted"
    Assert-True (Save-EulaAcceptance -Method "flag") "duplicate record was not replaced"

    $BadLines = [IO.File]::ReadAllLines($Current)
    $BadLines[4] = "accepted_at=not-a-canonical-time"
    [IO.File]::WriteAllLines($Current, $BadLines)
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "malformed acceptance time was accepted"
    Assert-True (Save-EulaAcceptance -Method "flag") "malformed record was not replaced"

    [IO.File]::WriteAllText($Current, (("x" * ($EulaRecordMaxBytes + 1)) -join ""))
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "oversized record was accepted"
    Assert-True (Save-EulaAcceptance -Method "flag") "oversized record was not replaced"

    $FileSddl = (Get-Acl -LiteralPath $Current).Sddl
    Add-EveryoneWriteRule -LiteralPath $Current
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "record writable by Everyone was accepted"
    Restore-Sddl -LiteralPath $Current -Sddl $FileSddl
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Current) "record ACL restoration was rejected"

    $CurrentDirectory = Split-Path -Parent $Current
    $DirectorySddl = (Get-Acl -LiteralPath $CurrentDirectory).Sddl
    Add-EveryoneWriteRule -LiteralPath $CurrentDirectory
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "record in an Everyone-writable directory was accepted"
    Restore-Sddl -LiteralPath $CurrentDirectory -Sddl $DirectorySddl
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Current) "directory ACL restoration was rejected"

    $env:USERPROFILE = Join-Path $Temporary "reparse-profile"
    New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
    $ReparseTarget = Join-Path $Temporary "reparse-target"
    $ReparseDirectory = Join-Path $ReparseTarget ".syntaur"
    New-Item -ItemType Directory -Path $ReparseDirectory -Force | Out-Null
    Write-LegacyRecord -Record (Join-Path $ReparseDirectory "eula-accepted")
    New-Item -ItemType Junction -Path (Join-Path $env:USERPROFILE ".syntaur") -Target $ReparseDirectory | Out-Null
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath (Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"))) "reparse-point acceptance directory was trusted"

    $env:USERPROFILE = Join-Path $Temporary "future"
    New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
    Assert-True (Save-EulaAcceptance -Method "flag") "future-version fixture was not stored"
    $Future = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    $EulaVersion = "2.0"
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Future)) "record crossed an EULA version"

    Write-Host "EULA acceptance tests passed"
} finally {
    $env:USERPROFILE = $OriginalUserProfile
    $env:SYNTAUR_INSTALL_TEST_LIBRARY_ONLY = $OriginalLibraryOnly
    Remove-Item -LiteralPath $Temporary -Recurse -Force -ErrorAction SilentlyContinue
}
