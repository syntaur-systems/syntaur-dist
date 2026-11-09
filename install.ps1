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
# Pass --quiet to suppress MSI dialogs for an authorized unattended server install.
# This does not accept the EULA or grant installation privileges.
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Brand = "Syntaur"
# MUST match the VERSION file at repo root. Run scripts/sync-version.sh
# before tagging a release so this and install.sh stay in sync with the
# workspace version in Cargo.toml. install.ps1 ships standalone.
$Version = "0.7.351"
$DistWorkflowCommit = "a045ce29a72476d5e173bc2d8be384eb5147a235"
$EulaSourceCommit = "8811aa006673caa5082a7c9343e83c0b7ac51d16"
$Binary = "syntaur.exe"
$ServerMsiSha256 = "0e0399df224aa4b4f732e23d9a3579107fad05aeeb3427ce3c311ecec8fc8642"
$InstallDir = "$env:LOCALAPPDATA\Syntaur"
$GatewaySha256 = "18fe03441a19ca18721673f4c106aed2858460f2c3e84a69e22b8ba53b6c74ae"
$ViewerSha256 = "863e5af5106257747957ffccd98ee88983af280ef2bd3bb8980f7510cccdf2de"
$LinkClientTorSha256 = "d322703f92c89fe6c9525e034a664802cd24e53b4771dbaf6ea471b770fb7024"
$LinkProbeSha256 = "76aed7ae80d3e78551cd83831d40eb08fe8719b3fb5594da199d3cfbbad56a79"
$SnowflakeClientSha256 = "f1db7ba494f81dd89e0d81c1e8eb775e60a72bf0fd4b7271ed7f7168cc4ad4d4"
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
        [Parameter(Mandatory = $true)][string]$Label,
        [ValidateRange(1,60000)][int]$TimeoutMs = 60000
    )
    if ($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $ExpectedSha256 -ceq ('0' * 64)) {
        throw "the installer has no valid pinned hash for $Label"
    }
    $Directory = Split-Path -Parent $LiteralPath
    $Temporary = Join-Path $Directory ((Split-Path -Leaf $LiteralPath) + ".part." + [Guid]::NewGuid().ToString("N"))
    $Backup = $null
    $Request = $null
    $Response = $null
    $ResponseStream = $null
    $FileStream = $null
    try {
        $Uri = [System.Uri]$Url
        if ($Uri.Scheme -ne [System.Uri]::UriSchemeHttps -and
            -not ($Uri.Scheme -eq [System.Uri]::UriSchemeHttp -and $Uri.IsLoopback)) {
            throw "download URL scheme must be HTTPS (or HTTP on loopback for testing)"
        }
        $MaxRedirects = 5
        $RedirectCount = 0
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $CurrentUri = $Uri

        while ($true) {
            $RemainingMs = [int]($TimeoutMs - $Stopwatch.ElapsedMilliseconds)
            if ($RemainingMs -le 0) {
                throw "$Label download exceeded enclosing deadline of $TimeoutMs ms"
            }

            $Request = [System.Net.HttpWebRequest]::Create($CurrentUri)
            $Request.AllowAutoRedirect = $false
            $Request.Timeout = $RemainingMs
            $Request.ReadWriteTimeout = $RemainingMs
            $Request.KeepAlive = $false

            try {
                $Response = [System.Net.HttpWebResponse]$Request.GetResponse()
            } catch [System.Net.WebException] {
                if ($null -ne $_.Exception.Response) {
                    $Response = [System.Net.HttpWebResponse]$_.Exception.Response
                } else {
                    throw
                }
            }

            $StatusCode = [int]$Response.StatusCode
            if ($StatusCode -in 301, 302, 303, 307, 308) {
                $Location = $Response.GetResponseHeader("Location")
                $Response.Close()
                $Response.Dispose()
                $Response = $null
                $Request = $null

                if ([string]::IsNullOrEmpty($Location)) {
                    throw "redirect response missing Location header for $Label"
                }
                $RedirectCount++
                if ($RedirectCount -gt $MaxRedirects) {
                    throw "too many redirects encountered for $Label"
                }
                $NextUri = [System.Uri]::new($CurrentUri, $Location)
                if ($CurrentUri.Scheme -eq [System.Uri]::UriSchemeHttps -and $NextUri.Scheme -ne [System.Uri]::UriSchemeHttps) {
                    throw "prohibited redirect downgrade from HTTPS to non-HTTPS for $Label"
                }
                if ($NextUri.Scheme -ne [Uri]::UriSchemeHttps -and
                    -not ($NextUri.Scheme -eq [Uri]::UriSchemeHttp -and $NextUri.IsLoopback)) {
                    throw "unsupported redirect URL for $Label"
                }
                $CurrentUri = $NextUri
                continue
            }

            if ($StatusCode -lt 200 -or $StatusCode -ge 300) {
                throw "$Label download failed with HTTP status code $StatusCode"
            }
            break
        }

        $MaxBytes = 1073741824L
        if ($Response.ContentLength -gt $MaxBytes) { throw "$Label download exceeds its size bound" }
        $FileStream = New-Object -TypeName System.IO.FileStream -ArgumentList @($Temporary, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $ResponseStream = $Response.GetResponseStream()

        $Buffer = New-Object -TypeName byte[] -ArgumentList 65536
        $TotalBytes = 0L

        while ($true) {
            $RemainingMs = [int]($TimeoutMs - $Stopwatch.ElapsedMilliseconds)
            if ($RemainingMs -le 0) {
                throw "$Label download exceeded enclosing deadline of $TimeoutMs ms"
            }
            if (-not $ResponseStream.CanTimeout) { throw 'Download stream does not support bounded reads' }
            $ResponseStream.ReadTimeout = $RemainingMs
            $BytesRead = $ResponseStream.Read($Buffer, 0, $Buffer.Length)
            if ($BytesRead -le 0) {
                break
            }
            $TotalBytes += $BytesRead
            if ($TotalBytes -gt $MaxBytes) {
                throw "$Label download exceeded size bound of $MaxBytes bytes"
            }
            $FileStream.Write($Buffer, 0, $BytesRead)
        }

        if ($Stopwatch.ElapsedMilliseconds -ge $TimeoutMs) { throw "$Label download exceeded enclosing deadline of $TimeoutMs ms" }
        $FileStream.Flush()
        $FileStream.Close()
        $FileStream.Dispose()
        $FileStream = $null

        $ResponseStream.Close()
        $ResponseStream.Dispose()
        $ResponseStream = $null

        $Response.Close()
        $Response.Dispose()
        $Response = $null
        $Request = $null

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
        # Abort owned network IO before disposing a partially-read response.
        if ($null -ne $Request) {
            try { $Request.Abort() } catch {}
            $Request = $null
        }
        if ($null -ne $FileStream) {
            try { $FileStream.Dispose() } catch {}
        }
        if ($null -ne $ResponseStream) {
            try { $ResponseStream.Dispose() } catch {}
        }
        if ($null -ne $Response) {
            try { $Response.Close(); $Response.Dispose() } catch {}
        }
        if (Test-Path -LiteralPath $Temporary) {
            Remove-Item -LiteralPath $Temporary -Force -ErrorAction SilentlyContinue
        }
        if ($Backup -and (Test-Path -LiteralPath $Backup)) {
            Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-SyntaurServerPackage {
    param([switch]$Quiet)
    # The same standalone MSI is distributed directly and through the Store.
    # EULA acceptance above is explicit; elevation remains normal Windows UAC.
    $Directory = Join-Path ([IO.Path]::GetTempPath()) ("Syntaur-Setup-" + [Guid]::NewGuid().ToString("N"))
    $Package = Join-Path $Directory 'syntaur-server-windows-x86_64.msi'
    $HeldPackage = $null
    try {
        Assert-PrivateInstallDirectory -LiteralPath $Directory
        Install-PinnedReleaseAsset -Url "https://github.com/syntaur-systems/syntaur-dist/releases/download/v$Version/syntaur-server-windows-x86_64.msi" `
            -LiteralPath $Package -ExpectedSha256 $ServerMsiSha256 -Label 'Syntaur server installer'
        # Retain read sharing only until Windows Installer exits: another process
        # cannot replace or modify these verified bytes during elevation.
        $HeldPackage = [IO.File]::Open($Package, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ServerMsiSha256) {
            throw 'Syntaur server installer changed before verification.'
        }
        $Signature = Get-AuthenticodeSignature -LiteralPath $Package
        if ($Signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            $null -eq $Signature.SignerCertificate -or $null -eq $Signature.TimeStamperCertificate -or
            $Signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -cne 'SYNTAUR ENTERPRISES LLC') {
            throw 'Syntaur server installer is not timestamped and trusted for SYNTAUR ENTERPRISES LLC.'
        }
        $Installer = Join-Path $env:windir 'System32\msiexec.exe'
        # Keep the unelevated MSI client with the initiating user. Windows
        # Installer requests elevation for per-machine actions itself; explicitly
        # using RunAs would change UserSID when another administrator consents.
        $InstallerArgs = @('/i', ('"' + $Package + '"'), 'ACCEPT_EULA=Yes', '/norestart')
        if ($Quiet) { $InstallerArgs += '/qn' }
        $Process = Start-Process -FilePath $Installer -Wait -PassThru `
            -ArgumentList $InstallerArgs
        if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
            throw "Windows Installer did not complete Syntaur setup (code $($Process.ExitCode))."
        }
        if ($Process.ExitCode -eq 3010) { Write-Host 'Syntaur installed. Windows requests a restart.' }
        else { Write-Host 'Syntaur installed. Open Syntaur from the Start menu to set up your server.' }
    } finally {
        if ($null -ne $HeldPackage) { $HeldPackage.Dispose() }
        if (Test-Path -LiteralPath $Package) { Remove-Item -LiteralPath $Package -Force }
        if (Test-Path -LiteralPath $Directory) { Remove-Item -LiteralPath $Directory }
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
$Mode = "server"
if ($args -contains "--server") { $Mode = "server" }
if ($args -contains "--connect") { $Mode = "connect" }

# Detect architecture
$Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else {
    Write-Host "Error: 32-bit Windows is not supported." -ForegroundColor Red
    exit 1
}

Write-Host "  Platform: windows-$Arch"
Write-Host ""
if ($Mode -eq 'server') {
    Install-SyntaurServerPackage -Quiet:($args -contains "--quiet")
    exit 0
}

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
