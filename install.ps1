# Syntaur installer for Windows — https://syntaur.app
# Usage:
#   irm https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.ps1 | iex   # interactive
#
# To pass flags (piped iex cannot receive them — it never populates $args):
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
$Version = "0.7.114"
$DistWorkflowCommit = "8811aa006673caa5082a7c9343e83c0b7ac51d16"
$EulaSourceCommit = "8811aa006673caa5082a7c9343e83c0b7ac51d16"
$Binary = "syntaur.exe"
$InstallDir = "$env:LOCALAPPDATA\Syntaur"
$DashboardUrl = "http://localhost:18789"
$EulaVersion = "1.0"
$EulaUrl = "https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/$EulaSourceCommit/EULA.md"
$EulaSha256 = "3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720"
$EulaRecordFormat = "1"
$EulaRecordMaxBytes = 4096

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
        [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier]$CurrentSid
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
        if (($Rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) {
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

function Test-CurrentEulaRecord {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
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
        if ($Key -ne $ExpectedKeys[$Index] -or $Values.ContainsKey($Key)) { return $false }
        $Values[$Key] = $Lines[$Index].Substring($Separator + 1)
    }
    if ($Values["record_format"] -ne $EulaRecordFormat) { return $false }
    if ($Values["eula_sha256"] -ne $EulaSha256) { return $false }
    if ($Values["eula_version"] -ne $EulaVersion) { return $false }
    if ($Values["eula_url"] -ne $EulaUrl) { return $false }
    if ($Values["accepted_at"] -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') {
        return $false
    }
    if ($Values["method"] -notin @("flag", "prompt")) { return $false }
    return $Values["installer_version"] -match '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

function Save-EulaAcceptance {
    param([Parameter(Mandatory = $true)][ValidateSet("flag", "prompt")][string]$Method)
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
            "accepted_at=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            "method=$Method"
            "installer_version=$Version"
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

function Confirm-EulaAcceptance {
    param([Parameter(Mandatory = $true)][bool]$AcceptByFlag)
    $Record = Join-Path (Join-Path $env:USERPROFILE ".syntaur") "eula-accepted"
    if (Test-CurrentEulaRecord -LiteralPath $Record) {
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

# Download gateway binary (server mode only)
if ($Mode -eq "server") {
    $DownloadUrl = "https://github.com/syntaur-systems/syntaur-dist/releases/download/v$Version/syntaur-gateway-windows-$Arch.exe"
    Write-Host "  Downloading $Brand server..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinaryPath -UseBasicParsing
    } catch {
        Write-Host ""
        Write-Host "  Note: Download server not yet available." -ForegroundColor Yellow
        Write-Host "  For now, copy the binary manually to $BinaryPath"
        Write-Host "  Then run: $Binary"
        Write-Host ""
        exit 0
    }
}

# Download viewer (lightweight dashboard window — no full browser needed)
$ViewerBinary = "syntaur-viewer.exe"
$ViewerPath = Join-Path $InstallDir $ViewerBinary
$ViewerUrl = "https://github.com/syntaur-systems/syntaur-dist/releases/download/v$Version/syntaur-viewer-windows-$Arch.exe"

Write-Host "  Downloading dashboard viewer..."
try {
    Invoke-WebRequest -Uri $ViewerUrl -OutFile $ViewerPath -UseBasicParsing
    Write-Host "  Viewer installed"
} catch {
    Write-Host "  Viewer download not available — shortcuts will open in browser" -ForegroundColor Yellow
}

$IconPath = Join-Path $InstallDir "syntaur-icon.ico"
$IconUrl = "https://github.com/syntaur-systems/syntaur-dist/releases/download/v$Version/syntaur-icon.ico"
Write-Host "  Downloading launcher icon..."
try {
    Invoke-WebRequest -Uri $IconUrl -OutFile $IconPath -UseBasicParsing
    Write-Host "  Launcher icon installed"
} catch {
    Write-Host "  Launcher icon not available — shortcut will use the app default" -ForegroundColor Yellow
}

# Determine shortcut target: use viewer if available, otherwise URL
if (Test-Path $ViewerPath) {
    $ShortcutTarget = $ViewerPath
    $ShortcutWorkDir = $InstallDir
} else {
    $ShortcutTarget = $DashboardUrl
    $ShortcutWorkDir = ""
}

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
if ($ShortcutWorkDir) { $Shortcut.WorkingDirectory = $ShortcutWorkDir }
if ($ShortcutIcon) { $Shortcut.IconLocation = $ShortcutIcon }
$Shortcut.Description = "Syntaur - Your personal AI platform"
$Shortcut.Save()

Write-Host "  Start Menu shortcut installed"

# --- Create Desktop shortcut ---
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Syntaur.lnk"

$Shortcut = $WshShell.CreateShortcut($DesktopShortcut)
$Shortcut.TargetPath = $ShortcutTarget
if ($ShortcutWorkDir) { $Shortcut.WorkingDirectory = $ShortcutWorkDir }
if ($ShortcutIcon) { $Shortcut.IconLocation = $ShortcutIcon }
$Shortcut.Description = "Syntaur - Your personal AI platform"
$Shortcut.Save()

Write-Host "  Desktop shortcut installed"

# --- URL shortcut on Desktop (opens in default browser) ---
# Parallel to the .lnk above but triggers the system browser instead of the
# viewer app. Users who prefer their real browser (saved logins, extensions)
# double-click this one. Only created when SYNTAUR_URL is set (remote
# gateway case); local installs don't need it.
if ($env:SYNTAUR_URL) {
    $UrlShortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Syntaur (Browser).url"
    @"
[InternetShortcut]
URL=$env:SYNTAUR_URL
IconIndex=0
"@ | Out-File -FilePath $UrlShortcutPath -Encoding ASCII
    Write-Host "  Browser shortcut on Desktop: Syntaur (Browser).url"
}

# --- Tailscale auto-setup (Tier 2 onboarding) ---
# If the caller passed a Tailscale pre-auth key via SYNTAUR_TS_AUTHKEY
# (the personalized-invite path mints one and bakes it into the command
# you send to a family member), bring Tailscale up on this machine so the
# viewer can reach the household gateway the moment it launches.
if ($env:SYNTAUR_TS_AUTHKEY) {
    Write-Host ""
    Write-Host "  Setting up Tailscale..."

    $TailscaleInstalled = $false
    $TsPath = "${env:ProgramFiles}\Tailscale\tailscale.exe"
    if (Test-Path $TsPath) {
        $TailscaleInstalled = $true
    } else {
        # Use Tailscale's official MSI installer. Silent install requires
        # admin — if the user isn't admin, fall back to opening the
        # download page and leave the join step for the viewer's
        # onboarding screen to detect.
        $TsMsiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.msi"
        $TsMsiPath = Join-Path $env:TEMP "tailscale-setup.msi"
        Write-Host "  Downloading Tailscale installer..."
        try {
            Invoke-WebRequest -Uri $TsMsiUrl -OutFile $TsMsiPath -UseBasicParsing
            # /qb = basic UI (progress bar only). Users without admin rights
            # will see UAC prompt here; that's unavoidable for any Windows
            # system install.
            $msi = Start-Process msiexec.exe -ArgumentList "/i `"$TsMsiPath`" /qb" -Wait -PassThru
            if ($msi.ExitCode -eq 0 -and (Test-Path $TsPath)) {
                $TailscaleInstalled = $true
            }
        } catch {
            Write-Host "  ! Tailscale install failed. Open https://tailscale.com/download/windows to install manually." -ForegroundColor Yellow
        }
    }

    if ($TailscaleInstalled) {
        try {
            & $TsPath up --authkey="$env:SYNTAUR_TS_AUTHKEY" --accept-routes
            Write-Host "  $([char]0x2713) Tailscale connected to your household tailnet" -ForegroundColor Green
        } catch {
            Write-Host "  ! tailscale up failed. You can retry:" -ForegroundColor Yellow
            Write-Host "    `"$TsPath`" up --authkey=`$env:SYNTAUR_TS_AUTHKEY --accept-routes"
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
    Write-Host "  To access from your phone or other computers:"
    Write-Host "    1. Install Tailscale on this computer and your other devices"
    Write-Host "    2. Open the Tailscale URL shown in the Syntaur dashboard"
} else {
    Write-Host "  $([char]0x2713) $Brand viewer installed" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Open Syntaur from the Start Menu to connect to your server."
    Write-Host "  The setup wizard will ask for your server address."
}
Write-Host ""
