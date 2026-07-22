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

function Write-HistoricalRecord {
    param([string]$Record, [string]$EulaHash)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Record) | Out-Null
    [IO.File]::WriteAllLines(
        $Record,
        @(
            "record_format=1",
            "eula_version=1.0",
            "eula_sha256=$EulaHash",
            "eula_url=https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md",
            "accepted_at=2026-07-17T13:58:33Z",
            "method=prompt",
            "installer_version=0.7.114"
        ),
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
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
    $ExpectedUrl = "https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/$EulaSourceCommit/EULA.md"
    Assert-True ($EulaUrl -eq $ExpectedUrl) "installer EULA URL is not commit-pinned"
    git -C $Repository diff --quiet $EulaSourceCommit -- EULA.md
    Assert-True ($LASTEXITCODE -eq 0) "commit-pinned EULA bytes do not match the accepted hash"

    $env:USERPROFILE = Join-Path $Temporary "historical"
    $Historical = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    Write-HistoricalRecord -Record $Historical -EulaHash $ExpectedHash
    $BeforeLines = [IO.File]::ReadAllLines($Historical)
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $true) "historical record was not migrated"
    $AfterLines = [IO.File]::ReadAllLines($Historical)
    Assert-True ($AfterLines[3] -eq "eula_url=$ExpectedUrl") "historical URL was not migrated"
    foreach ($Index in @(0, 1, 2, 4, 5, 6)) {
        Assert-True ($AfterLines[$Index] -eq $BeforeLines[$Index]) "migration changed evidence line $Index"
    }
    $FirstMigrationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Historical).Hash
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $false) "migrated record was not reused"
    $SecondMigrationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Historical).Hash
    Assert-True ($FirstMigrationHash -eq $SecondMigrationHash) "second migration rewrote evidence"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Historical) -Filter ".eula-accepted.tmp.*")
    Assert-True ($Residue.Count -eq 0) "migration left temporary files"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Historical) -Filter ".eula-accepted.backup.*")
    Assert-True ($Residue.Count -eq 0) "migration left backup files"

    $env:USERPROFILE = Join-Path $Temporary "legacy"
    $Legacy = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    Write-LegacyRecord -Record $Legacy
    $Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $Legacy).Hash
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Legacy)) "hashless legacy record was accepted"
    Assert-True (-not (Move-HistoricalEulaRecord -LiteralPath $Legacy)) "hashless legacy record was migrated"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $Legacy).Hash -eq $Before) "legacy rejection rewrote evidence"
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $true) "legacy record was not upgraded"
    $After = (Get-FileHash -Algorithm SHA256 -LiteralPath $Legacy).Hash
    Assert-True ($Before -ne $After) "legacy record was not replaced with hash-bound evidence"
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Legacy) "upgraded record was rejected"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Legacy) -Filter ".eula-accepted.tmp.*")
    Assert-True ($Residue.Count -eq 0) "legacy upgrade left temporary files"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Legacy) -Filter ".eula-accepted.backup.*")
    Assert-True ($Residue.Count -eq 0) "legacy upgrade left backup files"

    $env:USERPROFILE = Join-Path $Temporary "current"
    New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
    Assert-True (Save-EulaAcceptance -Method "prompt") "current record was not stored"
    $Current = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    Assert-True (Test-CurrentEulaRecord -LiteralPath $Current) "current record was rejected"
    $BeforeCurrentReuse = (Get-FileHash -Algorithm SHA256 -LiteralPath $Current).Hash
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $false) "current record was not reused"
    $AfterCurrentReuse = (Get-FileHash -Algorithm SHA256 -LiteralPath $Current).Hash
    Assert-True ($BeforeCurrentReuse -eq $AfterCurrentReuse) "current reuse rewrote its evidence"
    $OriginalDistWorkflowCommit = $DistWorkflowCommit
    $DistWorkflowCommit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    Assert-True ($EulaUrl -eq $ExpectedUrl) "dist commit rotation changed EULA authority"
    $BeforeNewDistReuse = (Get-FileHash -Algorithm SHA256 -LiteralPath $Current).Hash
    Assert-True (Confirm-EulaAcceptance -AcceptByFlag $false) "same EULA was rejected after the dist commit changed"
    $AfterNewDistReuse = (Get-FileHash -Algorithm SHA256 -LiteralPath $Current).Hash
    Assert-True ($BeforeNewDistReuse -eq $AfterNewDistReuse) "same-EULA reuse rewrote its evidence"
    $DistWorkflowCommit = $OriginalDistWorkflowCommit
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Current) -Filter ".eula-accepted.tmp.*")
    Assert-True ($Residue.Count -eq 0) "atomic record write left temporary files"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Current) -Filter ".eula-accepted.backup.*")
    Assert-True ($Residue.Count -eq 0) "atomic record replacement left backup files"

    $InvalidHistoricalCases = @(
        @{ Name = "raw-main"; Index = 3; Value = "eula_url=https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/main/EULA.md" },
        @{ Name = "url-case"; Index = 3; Value = "eula_url=https://github.com/syntaur-systems/syntaur-dist/blob/main/eula.md" },
        @{ Name = "url-query"; Index = 3; Value = "eula_url=https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md?download=1" },
        @{ Name = "schema"; Index = 0; Value = "record_format=2" },
        @{ Name = "version"; Index = 1; Value = "eula_version=2.0" },
        @{ Name = "hash"; Index = 2; Value = ("eula_sha256=" + ("a" * 64)) },
        @{ Name = "time"; Index = 4; Value = "accepted_at=not-a-time" },
        @{ Name = "method"; Index = 5; Value = "method=automatic" },
        @{ Name = "installer"; Index = 6; Value = "installer_version=01.7.114" }
    )
    foreach ($Case in $InvalidHistoricalCases) {
        $env:USERPROFILE = Join-Path $Temporary ("historical-" + $Case.Name)
        $Record = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
        Write-HistoricalRecord -Record $Record -EulaHash $ExpectedHash
        $Lines = [IO.File]::ReadAllLines($Record)
        $Lines[$Case.Index] = $Case.Value
        [IO.File]::WriteAllLines($Record, $Lines)
        $BeforeRejectedMigration = (Get-FileHash -Algorithm SHA256 -LiteralPath $Record).Hash
        Assert-True (-not (Move-HistoricalEulaRecord -LiteralPath $Record)) ("invalid historical record was migrated: " + $Case.Name)
        Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $Record).Hash -eq $BeforeRejectedMigration) ("invalid migration rewrote evidence: " + $Case.Name)
    }

    $env:USERPROFILE = Join-Path $Temporary "historical-unsafe"
    $UnsafeHistorical = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    Write-HistoricalRecord -Record $UnsafeHistorical -EulaHash $ExpectedHash
    $UnsafeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $UnsafeHistorical).Hash
    $UnsafeFileSddl = (Get-Acl -LiteralPath $UnsafeHistorical).Sddl
    Add-EveryoneWriteRule -LiteralPath $UnsafeHistorical
    Assert-True (-not (Move-HistoricalEulaRecord -LiteralPath $UnsafeHistorical)) "unsafe historical record was migrated"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $UnsafeHistorical).Hash -eq $UnsafeHash) "unsafe migration rewrote evidence"
    Restore-Sddl -LiteralPath $UnsafeHistorical -Sddl $UnsafeFileSddl
    $UnsafeDirectory = Split-Path -Parent $UnsafeHistorical
    $UnsafeDirectorySddl = (Get-Acl -LiteralPath $UnsafeDirectory).Sddl
    Add-EveryoneWriteRule -LiteralPath $UnsafeDirectory
    Assert-True (-not (Move-HistoricalEulaRecord -LiteralPath $UnsafeHistorical)) "historical record in unsafe directory was migrated"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $UnsafeHistorical).Hash -eq $UnsafeHash) "unsafe-directory migration rewrote evidence"
    Restore-Sddl -LiteralPath $UnsafeDirectory -Sddl $UnsafeDirectorySddl

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

    $BadLines = [IO.File]::ReadAllLines($Current)
    $BadLines[3] = "eula_url=https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/main/EULA.md"
    [IO.File]::WriteAllLines($Current, $BadLines)
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "unpinned EULA provenance was accepted"
    Assert-True (Save-EulaAcceptance -Method "flag") "unpinned EULA provenance was not replaced"

    [IO.File]::WriteAllText($Current, (("x" * ($EulaRecordMaxBytes + 1)) -join ""))
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $Current)) "oversized record was accepted"
    Assert-True (Save-EulaAcceptance -Method "flag") "oversized record was not replaced"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Current) -Filter ".eula-accepted.tmp.*")
    Assert-True ($Residue.Count -eq 0) "record repairs left temporary files"
    $Residue = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Current) -Filter ".eula-accepted.backup.*")
    Assert-True ($Residue.Count -eq 0) "record repairs left backup files"

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
    Write-HistoricalRecord -Record (Join-Path $ReparseDirectory "eula-accepted") -EulaHash $ExpectedHash
    New-Item -ItemType Junction -Path (Join-Path $env:USERPROFILE ".syntaur") -Target $ReparseDirectory | Out-Null
    $ReparseRecord = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    $ReparseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ReparseRecord).Hash
    Assert-True (-not (Test-CurrentEulaRecord -LiteralPath $ReparseRecord)) "reparse-point acceptance directory was trusted"
    Assert-True (-not (Move-HistoricalEulaRecord -LiteralPath $ReparseRecord)) "reparse-point historical record was migrated"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $ReparseRecord).Hash -eq $ReparseHash) "reparse rejection rewrote evidence"

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
