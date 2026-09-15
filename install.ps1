# Syntaur installer for Windows - https://syntaur.app
# Usage:
#   irm https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.ps1 | iex   # interactive
#
# To pass flags (piped iex cannot receive them - it never populates $args):
#   & ([scriptblock]::Create((irm https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.ps1))) --server
#   & ([scriptblock]::Create((irm https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.ps1))) --connect
#
# Pass --accept-eula to accept the EULA non-interactively after reading the
# immutable commit-pinned URL printed by this installer.
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Brand = "Syntaur"
# MUST match the VERSION file at repo root. Run scripts/sync-version.sh
# before tagging a release so this and install.sh stay in sync with the
# workspace version in Cargo.toml. install.ps1 ships standalone.
$Version = "0.7.198"
$DistWorkflowCommit = "a8a67e26a19ad9a3c85621151e8dfb0a029b601c"
$EulaSourceCommit = "8811aa006673caa5082a7c9343e83c0b7ac51d16"
$Binary = "syntaur.exe"
$InstallDir = "$env:LOCALAPPDATA\Syntaur"
$GatewaySha256 = "0000000000000000000000000000000000000000000000000000000000000000"
$ViewerSha256 = "0000000000000000000000000000000000000000000000000000000000000000"
$LinkClientTorSha256 = "0000000000000000000000000000000000000000000000000000000000000000"
$LinkProbeSha256 = "0000000000000000000000000000000000000000000000000000000000000000"
$SnowflakeClientSha256 = "0000000000000000000000000000000000000000000000000000000000000000"
$DashboardUrl = "http://localhost:18789"
$EulaVersion = "1.0"
$EulaUrl = "https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/$EulaSourceCommit/EULA.md"
$EulaHistoricalUrl = "https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md"
$EulaSha256 = "3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720"
$EulaRecordFormat = "1"
$EulaRecordMaxBytes = 4096

function Test-SupportedWindowsInstallToken {
    try {
        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (
            $null -ne $Identity.User -and
            $null -ne $Identity.Owner -and
            $Identity.User.Value -ceq $Identity.Owner.Value
        )
    } catch {
        return $false
    }
}

function Test-SupportedExistingPrivateRoot {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return $true
    }
    try {
        $Item = Get-Item -LiteralPath $LiteralPath -Force
        if (-not [bool]$Item.PSIsContainer -or
            ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $false
        }
        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -eq $Identity.User) {
            return $false
        }
        return (Get-OwnerSid -LiteralPath $LiteralPath).Value -ceq $Identity.User.Value
    } catch {
        return $false
    }
}

function Install-PinnedReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $ExpectedSha256 -ceq ('0' * 64)) {
        throw "the installer has no valid pinned hash for $Label"
    }
    $Directory = Split-Path -Parent $LiteralPath
    $Temporary = Join-Path $Directory ((Split-Path -Leaf $LiteralPath) + ".part." + [Guid]::NewGuid().ToString("N"))
    $Backup = $null
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Temporary -UseBasicParsing
        $Item = Get-Item -LiteralPath $Temporary -Force
        if (-not [bool]$Item.PSIsContainer -and $Item.Length -gt 0 -and $Item.Length -le 1073741824) {
            $ActualSha256 = (Get-FileHash -LiteralPath $Temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        } else {
            throw "$Label download is empty or exceeds its size bound"
        }
        if ($ActualSha256 -cne $ExpectedSha256) {
            throw "$Label did not match the hash pinned into this signed installer"
        }
        if (Test-Path -LiteralPath $LiteralPath) {
            $Existing = Get-Item -LiteralPath $LiteralPath -Force
            if ([bool]$Existing.PSIsContainer -or
                ($Existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                -not (Test-SafeInstallEntry -LiteralPath $LiteralPath -Container $false)) {
                throw "the existing $Label path is unsafe"
            }
            $Backup = Join-Path $Directory ((Split-Path -Leaf $LiteralPath) + ".backup." + [Guid]::NewGuid().ToString("N"))
            [IO.File]::Replace($Temporary, $LiteralPath, $Backup, $true)
            Remove-Item -LiteralPath $Backup -Force -ErrorAction Stop
            $Backup = $null
        } else {
            [IO.File]::Move($Temporary, $LiteralPath)
        }
        if (-not (Test-SafeInstallEntry -LiteralPath $LiteralPath -Container $false)) {
            throw "the installed $Label path has unsafe authority"
        }
    } finally {
        if (Test-Path -LiteralPath $Temporary) {
            Remove-Item -LiteralPath $Temporary -Force -ErrorAction SilentlyContinue
        }
        if ($Backup -and (Test-Path -LiteralPath $Backup)) {
            Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-PrivateInstallDirectory {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        New-Item -ItemType Directory -Path $LiteralPath | Out-Null
    }
    if (-not (Test-SafeInstallEntry -LiteralPath $LiteralPath -Container $true)) {
        throw "unsafe Syntaur Link directory: $LiteralPath"
    }
}

function Save-LinkTorConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$TorDirectory,
        [Parameter(Mandatory = $true)][string]$TransportBinary
    )
    $StateDirectory = Join-Path $TorDirectory "state"
    $CacheDirectory = Join-Path $TorDirectory "cache"
    Assert-PrivateInstallDirectory -LiteralPath $TorDirectory
    Assert-PrivateInstallDirectory -LiteralPath $StateDirectory
    Assert-PrivateInstallDirectory -LiteralPath $CacheDirectory
    $ConfigPath = Join-Path $TorDirectory "client.json"
    if (Test-Path -LiteralPath $ConfigPath) {
        $Existing = Get-Item -LiteralPath $ConfigPath -Force
        if ([bool]$Existing.PSIsContainer -or
            ($Existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not (Test-SafeInstallEntry -LiteralPath $ConfigPath -Container $false)) {
            throw "the existing Syntaur Link transport configuration is unsafe"
        }
        if ($Existing.Length -le 0 -or $Existing.Length -gt 65536) {
            throw "the existing Syntaur Link transport configuration exceeds its bounds"
        }
        # Keep existing bridges and paths during ordinary updates.
        return
    }
    $BridgeLines = @(
        "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.antisip.com:3478,stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.nextcloud.com:3478,stun:stun.bethesda.net:3478,stun:stun.nextcloud.com:443 utls-imitate=hellorandomizedalpn",
        "Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.antisip.com:3478,stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.nextcloud.com:3478,stun:stun.bethesda.net:3478,stun:stun.nextcloud.com:443 utls-imitate=hellorandomizedalpn"
    )
    $Configuration = [ordered]@{
        schema = 2
        state_dir = $StateDirectory
        cache_dir = $CacheDirectory
        bridge_bundle = [ordered]@{
            schema = 1
            transport = "snowflake"
            bridge_lines = $BridgeLines
        }
        transport_binary = $TransportBinary
        bundled_transport = $true
    }
    $Temporary = Join-Path $TorDirectory (".client.json." + [Guid]::NewGuid().ToString("N"))
    $Backup = $null
    try {
        $Utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
        [IO.File]::WriteAllText($Temporary, ($Configuration | ConvertTo-Json -Depth 5), $Utf8)
        try {
            [IO.File]::Move($Temporary, $ConfigPath)
        } catch [IO.IOException] {
            if (-not (Test-SafeInstallEntry -LiteralPath $ConfigPath -Container $false)) {
                throw
            }
        }
        if (-not (Test-SafeInstallEntry -LiteralPath $ConfigPath -Container $false)) {
            throw "the Syntaur Link transport configuration has unsafe authority"
        }
    } finally {
        if (Test-Path -LiteralPath $Temporary) {
            Remove-Item -LiteralPath $Temporary -Force -ErrorAction SilentlyContinue
        }
        if ($Backup -and (Test-Path -LiteralPath $Backup)) {
            Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OwnerSid {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $Owner = (Get-Acl -LiteralPath $LiteralPath).Owner
    try {
        return (New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList @($Owner))
    } catch {
        $Account = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList @($Owner)
        return $Account.Translate([System.Security.Principal.SecurityIdentifier])
    }
}

function Test-SafeEulaDacl {
    param(
        [Parameter(Mandatory = $true)]$Acl,
        [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier]$CurrentSid,
        [bool]$IncludeInheritedChildren = $false
    )
    $TrustedSids = @(
        $CurrentSid.Value,
        "S-1-5-18",       # LocalSystem
        "S-1-5-32-544"    # BUILTIN\Administrators
    )
    $MutatingMask = [int64][Security.AccessControl.FileSystemRights]::WriteData `
        -bor [int64][Security.AccessControl.FileSystemRights]::AppendData `
        -bor [int64][Security.AccessControl.FileSystemRights]::WriteExtendedAttributes `
        -bor [int64][Security.AccessControl.FileSystemRights]::WriteAttributes `
        -bor [int64][Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles `
        -bor [int64][Security.AccessControl.FileSystemRights]::Delete `
        -bor [int64][Security.AccessControl.FileSystemRights]::ChangePermissions `
        -bor [int64][Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($Rule in $Acl.Access) {
        if ($Rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
            continue
        }
        if (-not $IncludeInheritedChildren -and
            ($Rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) {
            continue
        }
        if (([int64]$Rule.FileSystemRights -band $MutatingMask) -eq 0) {
            continue
        }
        try {
            $RuleSid = $Rule.IdentityReference.Translate(
                [Security.Principal.SecurityIdentifier]
            )
        } catch {
            return $false
        }
        if ($TrustedSids -notcontains $RuleSid.Value) {
            return $false
        }
    }
    return $true
}

function Test-SafeInstallEntry {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][bool]$Container
    )
    try {
        $Item = Get-Item -LiteralPath $LiteralPath -Force
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            [bool]$Item.PSIsContainer -ne $Container) {
            return $false
        }
        $CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($null -eq $CurrentSid -or
            (Get-OwnerSid -LiteralPath $LiteralPath).Value -cne $CurrentSid.Value) {
            return $false
        }
        return Test-SafeEulaDacl `
            -Acl (Get-Acl -LiteralPath $LiteralPath) `
            -CurrentSid $CurrentSid `
            -IncludeInheritedChildren $Container
    } catch {
        return $false
    }
}

function Test-SafeEulaEntry {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][bool]$Container
    )
    try {
        $Item = Get-Item -LiteralPath $LiteralPath -Force
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        if ([bool]$Item.PSIsContainer -ne $Container) { return $false }
        $Acl = Get-Acl -LiteralPath $LiteralPath
        $OwnerSid = Get-OwnerSid -LiteralPath $LiteralPath
        $CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $TrustedOwnerSids = @(
            $CurrentSid.Value,
            "S-1-5-18",       # LocalSystem
            "S-1-5-32-544"    # BUILTIN\Administrators
        )
        return $TrustedOwnerSids -contains $OwnerSid.Value `
            -and (Test-SafeEulaDacl -Acl $Acl -CurrentSid $CurrentSid)
    } catch {
        return $false
    }
}

function Test-EulaRecordForUrl {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$ExpectedUrl,
        [ref]$ValidatedValues
    )
    if ($null -ne $ValidatedValues) { $ValidatedValues.Value = $null }
    $Directory = Split-Path -Parent $LiteralPath
    if (-not (Test-SafeEulaEntry -LiteralPath $Directory -Container $true)) { return $false }
    if (-not (Test-SafeEulaEntry -LiteralPath $LiteralPath -Container $false)) { return $false }
    try {
        $Item = Get-Item -LiteralPath $LiteralPath -Force
        if ($Item.Length -le 0 -or $Item.Length -gt $EulaRecordMaxBytes) { return $false }
        $Lines = [IO.File]::ReadAllLines($LiteralPath)
    } catch {
        return $false
    }
    if ($Lines.Count -ne 7 -or -not $Lines[0].StartsWith("record_format=")) {
        return $false
    }
    $ExpectedKeys = @(
        "record_format", "eula_version", "eula_sha256", "eula_url",
        "accepted_at", "method", "installer_version"
    )
    $Values = @{}
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        $Separator = $Lines[$Index].IndexOf("=")
        if ($Separator -le 0) { return $false }
        $Key = $Lines[$Index].Substring(0, $Separator)
        if ($Key -cne $ExpectedKeys[$Index] -or $Values.ContainsKey($Key)) { return $false }
        $Values[$Key] = $Lines[$Index].Substring($Separator + 1)
    }
    if ($Values["record_format"] -cne $EulaRecordFormat) { return $false }
    if ($Values["eula_sha256"] -cne $EulaSha256) { return $false }
    if ($Values["eula_version"] -cne $EulaVersion) { return $false }
    if ($Values["eula_url"] -cne $ExpectedUrl) { return $false }
    if ($Values["accepted_at"] -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') {
        return $false
    }
    if ($Values["method"] -cnotin @("flag", "prompt")) { return $false }
    if ($Values["installer_version"] -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        return $false
    }
    if ($null -ne $ValidatedValues) { $ValidatedValues.Value = $Values }
    return $true
}

function Test-CurrentEulaRecord {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    return Test-EulaRecordForUrl -LiteralPath $LiteralPath -ExpectedUrl $EulaUrl
}

function Save-EulaAcceptance {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("flag", "prompt")][string]$Method,
        [string]$AcceptedAt = "",
        [string]$InstallerVersion = ""
    )
    if (($AcceptedAt -eq "") -xor ($InstallerVersion -eq "")) {
        throw "preserved EULA evidence must include both accepted_at and installer_version"
    }
    if ($AcceptedAt -eq "") {
        $AcceptedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $InstallerVersion = $Version
    }
    if ($AcceptedAt -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') {
        throw "preserved EULA acceptance time is invalid"
    }
    if ($InstallerVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "preserved EULA installer version is invalid"
    }
    $SyntaurDirectory = Join-Path $env:USERPROFILE ".syntaur"
    $Record = Join-Path $SyntaurDirectory "eula-accepted"
    $Temporary = $null
    $Backup = $null
    $Committed = $false
    try {
        if (Test-Path -LiteralPath $SyntaurDirectory) {
            if (-not (Test-SafeEulaEntry -LiteralPath $SyntaurDirectory -Container $true)) {
                throw "EULA acceptance directory authority is unsafe"
            }
        } else {
            New-Item -ItemType Directory -Path $SyntaurDirectory | Out-Null
            if (-not (Test-SafeEulaEntry -LiteralPath $SyntaurDirectory -Container $true)) {
                throw "new EULA acceptance directory authority is unsafe"
            }
        }
        if (Test-Path -LiteralPath $Record) {
            if (-not (Test-SafeEulaEntry -LiteralPath $Record -Container $false)) {
                throw "existing EULA acceptance record authority is unsafe"
            }
        }
        $Temporary = Join-Path $SyntaurDirectory (".eula-accepted.tmp." + [Guid]::NewGuid().ToString("N"))
        $Lines = @(
            "record_format=$EulaRecordFormat"
            "eula_version=$EulaVersion"
            "eula_sha256=$EulaSha256"
            "eula_url=$EulaUrl"
            "accepted_at=$AcceptedAt"
            "method=$Method"
            "installer_version=$InstallerVersion"
        )
        $Encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
        [IO.File]::WriteAllLines($Temporary, $Lines, $Encoding)
        if (Test-Path -LiteralPath $Record) {
            $Backup = Join-Path $SyntaurDirectory (".eula-accepted.backup." + [Guid]::NewGuid().ToString("N"))
            [IO.File]::Replace($Temporary, $Record, $Backup, $true)
            $Committed = $true
            Remove-Item -LiteralPath $Backup -Force -ErrorAction Stop
            $Backup = $null
        } else {
            [IO.File]::Move($Temporary, $Record)
            $Committed = $true
        }
        return Test-CurrentEulaRecord -LiteralPath $Record
    } catch {
        $Failure = $_
        $CleanupFailed = $false
        if ($Temporary -and (Test-Path -LiteralPath $Temporary)) {
            try {
                Remove-Item -LiteralPath $Temporary -Force -ErrorAction Stop
            } catch {
                $CleanupFailed = $true
            }
        }
        if ($Backup -and (Test-Path -LiteralPath $Backup)) {
            try {
                Remove-Item -LiteralPath $Backup -Force -ErrorAction Stop
                $Backup = $null
            } catch {
                $CleanupFailed = $true
            }
        }
        if ($Committed -and (-not $CleanupFailed) -and (Test-CurrentEulaRecord -LiteralPath $Record)) {
            return $true
        }
        if ($env:SYNTAUR_INSTALL_TEST_LIBRARY_ONLY -eq "1") {
            throw $Failure
        }
        return $false
    }
}

function Move-HistoricalEulaRecord {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $ExpectedPath = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    if ($LiteralPath -ne $ExpectedPath) { return $false }
    $ValidatedValues = $null
    if (-not (Test-EulaRecordForUrl `
        -LiteralPath $LiteralPath `
        -ExpectedUrl $EulaHistoricalUrl `
        -ValidatedValues ([ref]$ValidatedValues))) {
        return $false
    }
    if (-not (Save-EulaAcceptance `
        -Method $ValidatedValues["method"] `
        -AcceptedAt $ValidatedValues["accepted_at"] `
        -InstallerVersion $ValidatedValues["installer_version"])) {
        return $false
    }
    return Test-CurrentEulaRecord -LiteralPath $LiteralPath
}

function Confirm-EulaAcceptance {
    param([Parameter(Mandatory = $true)][bool]$AcceptByFlag)
    $Record = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    if ((Test-CurrentEulaRecord -LiteralPath $Record) -or
        (Move-HistoricalEulaRecord -LiteralPath $Record)) {
        Write-Host "  EULA v$EulaVersion previously accepted; continuing."
        Write-Host ""
        return $true
    }
    if ($AcceptByFlag) {
        $Method = "flag"
    } else {
        Write-Host "  Installing $Brand requires accepting the End User License Agreement (v$EulaVersion):"
        Write-Host "    $EulaUrl"
        Write-Host ""
        $Answer = Read-Host '  Type "I AGREE" to accept (anything else aborts)'
        if ($Answer.Trim() -ine "I AGREE") {
            Write-Host "  EULA not accepted - install aborted."
            return $false
        }
        $Method = "prompt"
    }
    if (-not (Save-EulaAcceptance -Method $Method)) {
        Write-Warning "EULA acceptance could not be stored securely; a future installer may need to ask again."
    }
    Write-Host "  EULA v$EulaVersion accepted (via $Method)."
    Write-Host ""
    return $true
}

if ($env:SYNTAUR_INSTALL_TEST_LIBRARY_ONLY -eq "1") {
    return
}

# The gateway's private Windows data authority requires new objects to be
# owned by the launching user. An elevated/UAC-disabled shell can instead use
# BUILTIN\Administrators as its token owner and create state that a later
# normal login must reject. Refuse before EULA or filesystem mutation.
if (-not (Test-SupportedWindowsInstallToken)) {
    Write-Host ""
    Write-Host "Error: Syntaur must be installed from a normal, unelevated PowerShell session." -ForegroundColor Red
    Write-Host "Close this administrator window, open PowerShell normally, and run the installer again."
    exit 1
}

$PrivateDataRoot = Join-Path $env:USERPROFILE ".syntaur"
if (-not (Test-SupportedExistingPrivateRoot -LiteralPath $PrivateDataRoot)) {
    Write-Host ""
    Write-Host "Error: the existing $PrivateDataRoot directory is not owned by this Windows account or is a reparse point." -ForegroundColor Red
    Write-Host "Syntaur will not modify or take ownership of an untrusted data directory automatically."
    Write-Host "Back up and audit that directory, then move it aside or restore this account as its owner before reinstalling."
    exit 1
}

Write-Host ""
Write-Host "  $([char]0x265E) $Brand v$Version"
Write-Host "  Your personal AI platform"
Write-Host ""

# A matching exact-version record is durable acceptance; only a changed or
# invalid record requires another affirmative act.
if (-not (Confirm-EulaAcceptance -AcceptByFlag ($args -contains "--accept-eula"))) {
    exit 1
}

# Parse mode
$Mode = ""
if ($args -contains "--server") { $Mode = "server" }
if ($args -contains "--connect") { $Mode = "connect" }

if (-not $Mode) {
    Write-Host "  How would you like to use Syntaur?"
    Write-Host ""
    Write-Host "  1) Run the server on this computer"
    Write-Host "     Your AI runs here. Access from phone, laptop, any device."
    Write-Host "     (This computer needs to stay on.)"
    Write-Host ""
    Write-Host "  2) Connect to my Syntaur server"
    Write-Host "     Syntaur is already running elsewhere. Just install the viewer."
    Write-Host ""
    $Choice = Read-Host "  Choose [1/2]"
    $Mode = if ($Choice -eq "2") { "connect" } else { "server" }
    Write-Host ""
}

# Detect architecture
$Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else {
    Write-Host "Error: 32-bit Windows is not supported." -ForegroundColor Red
    exit 1
}

Write-Host "  Platform: windows-$Arch"
Write-Host ""

# Create install directory
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$BinaryPath = Join-Path $InstallDir $Binary

# Executable pins are stamped into this signed installer by release-sign.yml.
Assert-PrivateInstallDirectory -LiteralPath $InstallDir
$ReleaseBase = "https://github.com/syntaur-systems/syntaur-dist/releases/download/v$Version"
if ($Mode -eq "server") {
    Install-PinnedReleaseAsset -Url "$ReleaseBase/syntaur-gateway-windows-$Arch.exe" `
        -LiteralPath $BinaryPath -ExpectedSha256 $GatewaySha256 -Label "Syntaur server"
}
$ViewerBinary = "syntaur-viewer.exe"
$ViewerPath = Join-Path $InstallDir $ViewerBinary
Install-PinnedReleaseAsset -Url "$ReleaseBase/syntaur-viewer-windows-$Arch.exe" `
    -LiteralPath $ViewerPath -ExpectedSha256 $ViewerSha256 -Label "dashboard viewer"
foreach ($Helper in @(
    @{ Name = "syntaur-link-client-tor"; Hash = $LinkClientTorSha256 },
    @{ Name = "syntaur-link-probe"; Hash = $LinkProbeSha256 },
    @{ Name = "syntaur-snowflake-client"; Hash = $SnowflakeClientSha256 }
)) {
    Install-PinnedReleaseAsset -Url "$ReleaseBase/$($Helper.Name)-windows-$Arch.exe" `
        -LiteralPath (Join-Path $InstallDir "$($Helper.Name).exe") `
        -ExpectedSha256 $Helper.Hash -Label $Helper.Name
}
Save-LinkTorConfiguration -TorDirectory (Join-Path $InstallDir "link-tor") `
    -TransportBinary (Join-Path $InstallDir "syntaur-snowflake-client.exe")

$IconPath = Join-Path $InstallDir "syntaur-icon.ico"
$IconUrl = "https://github.com/syntaur-systems/syntaur-dist/releases/download/v$Version/syntaur-icon.ico"
Write-Host "  Downloading launcher icon..."
try {
    Invoke-WebRequest -Uri $IconUrl -OutFile $IconPath -UseBasicParsing
    Write-Host "  Launcher icon installed"
} catch {
    Write-Host "  Launcher icon not available - shortcut will use the app default" -ForegroundColor Yellow
}

# The verified native client owns local setup and device pairing.
$ShortcutTarget = $ViewerPath
$ShortcutWorkDir = $InstallDir
$ShortcutArguments = if ($Mode -eq "server") { "--local-owner" } else { "" }

if (Test-Path $IconPath) {
    $ShortcutIcon = $IconPath
} elseif (Test-Path $BinaryPath) {
    $ShortcutIcon = "$BinaryPath,0"
} elseif (Test-Path $ViewerPath) {
    $ShortcutIcon = "$ViewerPath,0"
} else {
    $ShortcutIcon = ""
}

# Add to PATH if not already there
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$InstallDir*") {
    Write-Host "  Adding $InstallDir to PATH..."
    [Environment]::SetEnvironmentVariable("PATH", "$InstallDir;$UserPath", "User")
    $env:PATH = "$InstallDir;$env:PATH"
}

# --- Create Start Menu shortcut ---
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartMenuShortcut = Join-Path $StartMenuDir "Syntaur.lnk"

$WshShell = New-Object -ComObject WScript.Shell

$Shortcut = $WshShell.CreateShortcut($StartMenuShortcut)
$Shortcut.TargetPath = $ShortcutTarget
$Shortcut.Arguments = $ShortcutArguments
if ($ShortcutWorkDir) { $Shortcut.WorkingDirectory = $ShortcutWorkDir }
if ($ShortcutIcon) { $Shortcut.IconLocation = $ShortcutIcon }
$Shortcut.Description = "Syntaur - Your personal AI platform"
$Shortcut.Save()

Write-Host "  Start Menu shortcut installed"

# --- Create Desktop shortcut ---
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Syntaur.lnk"

$Shortcut = $WshShell.CreateShortcut($DesktopShortcut)
$Shortcut.TargetPath = $ShortcutTarget
$Shortcut.Arguments = $ShortcutArguments
if ($ShortcutWorkDir) { $Shortcut.WorkingDirectory = $ShortcutWorkDir }
if ($ShortcutIcon) { $Shortcut.IconLocation = $ShortcutIcon }
$Shortcut.Description = "Syntaur - Your personal AI platform"
$Shortcut.Save()

Write-Host "  Desktop shortcut installed"
# Earlier installers also created a browser URL beside the native shortcut.
# Do not follow reparse points or remove a different kind of user document.
$LegacyBrowserShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Syntaur (Browser).url"
if (Test-Path -LiteralPath $LegacyBrowserShortcut -PathType Leaf) {
    $LegacyItem = Get-Item -LiteralPath $LegacyBrowserShortcut -Force
    if (($LegacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        $LegacyText = [IO.File]::ReadAllText($LegacyBrowserShortcut)
        if ($LegacyText -match '(?m)^\[InternetShortcut\]\r?$' -and $LegacyText -match '(?m)^URL=https?://') {
            Remove-Item -LiteralPath $LegacyBrowserShortcut -Force -ErrorAction Stop
        }
    }
}


# --- Auto-start via Startup folder (server mode only) ---
if ($Mode -eq "server") {
$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$StartupShortcut = Join-Path $StartupDir "Syntaur Service.lnk"

$Shortcut = $WshShell.CreateShortcut($StartupShortcut)
$Shortcut.TargetPath = $BinaryPath
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.WindowStyle = 7  # Minimized
$Shortcut.Description = "Syntaur AI Platform - background service"
$Shortcut.Save()

Write-Host "  Auto-start configured (runs at login)"
} # end server-only auto-start

# Clean up COM object
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null

Write-Host ""
if ($Mode -eq "server") {
    Write-Host "  $([char]0x2713) $Brand server installed" -ForegroundColor Green
    Write-Host ""
    Write-Host "  To start now:"
    Write-Host "    Start-Process '$BinaryPath'"
    Write-Host ""
    Write-Host "  Open Syntaur from the Start Menu or Desktop shortcut, or go to:"
    Write-Host "    $DashboardUrl"
    Write-Host ""
    Write-Host "  Install Syntaur on your other devices and choose Connect."
} else {
    Write-Host "  $([char]0x2713) $Brand viewer installed" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Open Syntaur from the Start Menu to connect to your server."
    Write-Host "  Syntaur will guide you through pairing with your household."
}
Write-Host ""
