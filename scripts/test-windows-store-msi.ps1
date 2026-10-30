# Pipeline scope: compatibility-channels — isolated validation of the native Store wrapper.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MsiPath,
    [string]$UpgradeMsiPath,
    [string]$BuilderPath,
    [string]$AssetDirectory,
    [string]$WixPath,
    [string]$CosignPath,
    [string]$NegativeOutputDirectory
)
$ErrorActionPreference = "Stop"
function Assert-Test { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Quote-Arg { param([string]$Value) Assert-Test (-not $Value.Contains('"')) "Quotes are not accepted in paths."; return '"' + $Value + '"' }
function Invoke-Msi {
    param([string]$Operation, [string]$Package, [string]$Log)
    $Arguments = "$Operation $(Quote-Arg $Package) /qn /norestart /L*v $(Quote-Arg $Log)"
    $Process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    Assert-Test ($Process.ExitCode -eq 0) "msiexec $Operation failed with exit code $($Process.ExitCode); log: $Log"
}
function Assert-MsiRejected {
    param([string]$Package, [string]$Log, [string]$Fixture, [string]$ExtraArguments = "")
    $Arguments = "/i $(Quote-Arg $Package) /qn /norestart /L*v $(Quote-Arg $Log) $ExtraArguments"
    $Process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($Process.ExitCode -eq 0) {
        $script:PackageInstalled = $true
        $script:CurrentMsi = $Package
        $CleanupLog = "$Log.cleanup-uninstall.log"
        $Cleanup = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $(Quote-Arg $Package) /qn /norestart /L*v $(Quote-Arg $CleanupLog)" -Wait -PassThru -WindowStyle Hidden
        Assert-Test ($Cleanup.ExitCode -eq 0) "Unsafe MSI fixture '$Fixture' unexpectedly succeeded (original exit 0; log: $Log), and immediate cleanup failed with exit code $($Cleanup.ExitCode); cleanup log: $CleanupLog"
        $script:PackageInstalled = $false
        throw "Unsafe MSI fixture '$Fixture' unexpectedly succeeded with original exit code 0; log: $Log; cleanup succeeded with exit code $($Cleanup.ExitCode); cleanup log: $CleanupLog"
    }
}
function Start-Native {
    param([string]$Launcher, [string]$Arguments)
    return Start-Process -FilePath $Launcher -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
}
function Test-AncestorAclCompatibility {
    param([string]$Launcher)
    $Assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Launcher))
    $Method = $Assembly.GetType("StoreClientLauncher", $true).GetMethod(
        "ValidateKnownFolderAncestors", [Reflection.BindingFlags]"NonPublic,Static")
    Assert-Test ($null -ne $Method) "Native ancestor validator was not found."
    $Fixture = Join-Path $env:TEMP ("syntaur-acl-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $Fixture | Out-Null
    $OriginalAcl = Get-Acl -LiteralPath $Fixture
    $Foreign = New-Object Security.Principal.SecurityIdentifier("S-1-1-0")
    $User = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $InvokeArguments = [object[]]@($Fixture.PSObject.BaseObject, $User.PSObject.BaseObject)
    try {
        $InheritOnly = New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $Foreign, [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::InheritOnly, [Security.AccessControl.AccessControlType]::Allow)
        $Acl = Get-Acl -LiteralPath $Fixture
        $Acl.AddAccessRule($InheritOnly)
        Set-Acl -LiteralPath $Fixture -AclObject $Acl
        $Method.Invoke($null, $InvokeArguments) | Out-Null

        Set-Acl -LiteralPath $Fixture -AclObject $OriginalAcl
        $ApplicableRights = [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions
        $Applicable = New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $Foreign, $ApplicableRights, [Security.AccessControl.InheritanceFlags]::None,
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $Acl = Get-Acl -LiteralPath $Fixture
        $Acl.AddAccessRule($Applicable)
        Set-Acl -LiteralPath $Fixture -AclObject $Acl
        $Rejected = $false
        try { $Method.Invoke($null, $InvokeArguments) | Out-Null }
        catch {
            $Exception = $_.Exception
            for ($Depth = 0; $Depth -lt 4 -and $null -ne $Exception.InnerException -and
                ($Exception -is [Reflection.TargetInvocationException] -or $Exception -is [Management.Automation.MethodInvocationException]); $Depth++) {
                $Exception = $Exception.InnerException
            }
            $ExpectedMessage = "An untrusted principal can replace or control a known-folder ancestor: " + (New-Object IO.DirectoryInfo($Fixture)).FullName
            if ($Exception -isnot [InvalidOperationException] -or $Exception.Message -cne $ExpectedMessage) { throw }
            $Rejected = $true
        }
        Assert-Test $Rejected "Applicable foreign Delete/ChangePermissions ACE was not rejected."
    } finally {
        Set-Acl -LiteralPath $Fixture -AclObject $OriginalAcl
        Remove-Item -LiteralPath $Fixture -Force
    }
}
function Get-StartupState {
    $Run = Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
    $RunValues = if ($null -eq $Run) { @() } else { @($Run.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object { "$($_.Name)=$($_.Value)" }) }
    $Startup = [Environment]::GetFolderPath("Startup")
    $Files = if (-not [string]::IsNullOrEmpty($Startup) -and (Test-Path -LiteralPath $Startup)) { @(Get-ChildItem -LiteralPath $Startup -Force | ForEach-Object { "$($_.Name):$($_.Length)" }) } else { @() }
    return (($RunValues | Sort-Object) -join "`n") + "|" + ($Files -join "`n") + "|" + [Environment]::GetEnvironmentVariable("Path", "User")
}
function Remove-EmptyDirectory {
    param([string]$LiteralPath)
    if ((Test-Path -LiteralPath $LiteralPath) -and @(Get-ChildItem -LiteralPath $LiteralPath -Force).Count -eq 0) { Remove-Item -LiteralPath $LiteralPath -Force }
}
function Assert-Bytes { param([string]$Path, [byte[]]$Expected, [string]$Stage)
    Assert-Test (Test-Path -LiteralPath $Path -PathType Leaf) "Missing marker during ${Stage}: $Path"
    Assert-Test ([Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($Path), $Expected)) "Marker changed during ${Stage}: $Path"
}
function Assert-BuilderRejected {
    param([hashtable]$Arguments, [string]$Fixture)
    try { & $BuilderPath @Arguments } catch { Write-Host "Expected builder rejection ($Fixture): $($_.Exception.Message)"; return }
    throw "Builder accepted negative fixture: $Fixture"
}

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
Assert-Test (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) "Use a disposable standard-user account, not an elevated administrator."
$Root = Join-Path $env:LOCALAPPDATA "Syntaur"
$Container = Join-Path $Root "Store"
$DataRoot = Join-Path $Container "Syntaur"
$Bin = Join-Path $DataRoot "bin"
$StoreConfig = Join-Path $DataRoot "link-tor\client.json"
$ShortcutPath = Join-Path ([Environment]::GetFolderPath("Programs")) "Syntaur Connect.lnk"
Assert-Test (-not (Test-Path -LiteralPath $Root)) "Refusing to touch any existing real Syntaur profile."
Assert-Test (-not (Test-Path -LiteralPath $ShortcutPath)) "Refusing to replace an existing Syntaur shortcut."
$Existing = @(Get-ChildItem -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue | Where-Object {
    (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).DisplayName -like "Syntaur Connect*" })
Assert-Test ($Existing.Count -eq 0) "Refusing to change an existing Syntaur package."
foreach ($Package in @($MsiPath, $UpgradeMsiPath) | Where-Object { $_ }) { Assert-Test (Test-Path -LiteralPath $Package -PathType Leaf) "MSI not found: $Package" }

$NegativeValues = @($BuilderPath, $AssetDirectory, $WixPath, $CosignPath, $NegativeOutputDirectory)
if (@($NegativeValues | Where-Object { $_ }).Count -gt 0) {
    Assert-Test (@($NegativeValues | Where-Object { $_ }).Count -eq 5) "All five negative-builder parameters are required together."
    Assert-Test (-not (Test-Path -LiteralPath $NegativeOutputDirectory)) "NegativeOutputDirectory must be new."
    New-Item -ItemType Directory -Path $NegativeOutputDirectory | Out-Null
    $Installer = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"))
    $Version = [regex]::Match($Installer, '(?m)^\$Version = "([^"]+)"$').Groups[1].Value
    Assert-Test ([bool]$Version) "Cannot read the installer version."
    foreach ($Fixture in @("wrong-hash", "missing-hash", "duplicate-hash")) {
        $FixtureAssets = Join-Path $NegativeOutputDirectory "$Fixture-assets"
        Copy-Item -LiteralPath $AssetDirectory -Destination $FixtureAssets -Recurse
        $ChecksumPath = Join-Path $FixtureAssets "checksums.txt"
        $Lines = [Collections.Generic.List[string]]::new()
        $Lines.AddRange([IO.File]::ReadAllLines($ChecksumPath))
        if ($Fixture -eq "wrong-hash") { $Lines[0] = ('0' * 64) + $Lines[0].Substring(64) }
        if ($Fixture -eq "missing-hash") { $Lines.RemoveAt(0) }
        if ($Fixture -eq "duplicate-hash") { $Lines.Add($Lines[0]) }
        [IO.File]::WriteAllLines($ChecksumPath, $Lines)
        Assert-BuilderRejected -Fixture "Cosign-rejection-$Fixture (not checksum-parser coverage)" -Arguments @{ Version = $Version; AssetDirectory = $FixtureAssets; OutputDirectory = (Join-Path $NegativeOutputDirectory "$Fixture-out"); WixPath = $WixPath; CosignPath = $CosignPath; DevelopmentUnsigned = $true }
    }
    $ChangedAssets = Join-Path $NegativeOutputDirectory "changed-original-assets"
    Copy-Item -LiteralPath $AssetDirectory -Destination $ChangedAssets -Recurse
    $ChangedViewer = Join-Path $ChangedAssets "syntaur-viewer-windows-x86_64.exe"
    $Stream = [IO.File]::Open($ChangedViewer, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $Stream.WriteByte(0) } finally { $Stream.Dispose() }
    Assert-BuilderRejected -Fixture "original-asset-hash-validation" -Arguments @{ Version = $Version; AssetDirectory = $ChangedAssets; OutputDirectory = (Join-Path $NegativeOutputDirectory "changed-original-out"); WixPath = $WixPath; CosignPath = $CosignPath; DevelopmentUnsigned = $true }
    $Junction = Join-Path $NegativeOutputDirectory "reparse-assets"
    New-Item -ItemType Junction -Path $Junction -Target $AssetDirectory | Out-Null
    Assert-BuilderRejected -Fixture "reparse" -Arguments @{ Version = $Version; AssetDirectory = $Junction; OutputDirectory = (Join-Path $NegativeOutputDirectory "reparse-out"); WixPath = $WixPath; CosignPath = $CosignPath; DevelopmentUnsigned = $true }
    Assert-BuilderRejected -Fixture "signing-denial" -Arguments @{ Version = $Version; AssetDirectory = $AssetDirectory; OutputDirectory = (Join-Path $NegativeOutputDirectory "signing-out"); WixPath = $WixPath; CosignPath = $CosignPath }
}

$DirectTor = Join-Path $Root "link-tor"
$DirectProfiles = Join-Path $Root "profiles"
New-Item -ItemType Directory -Path $DirectTor -Force | Out-Null
New-Item -ItemType Directory -Path $DirectProfiles | Out-Null
$Markers = @{
    (Join-Path $DirectTor "client.json") = [Text.Encoding]::UTF8.GetBytes("direct-channel configuration marker")
    (Join-Path $DirectProfiles "direct.marker") = [Text.Encoding]::UTF8.GetBytes("direct-channel profile marker")
    (Join-Path $Root "direct-window.marker") = [Text.Encoding]::UTF8.GetBytes("direct-channel window marker")
}
foreach ($Path in $Markers.Keys) { [IO.File]::WriteAllBytes($Path, $Markers[$Path]) }
$StoreMarkers = @{}
$LogBase = Join-Path $env:TEMP ("syntaur-store-test-" + [Guid]::NewGuid().ToString("N"))
$PackageInstalled = $false; $CurrentMsi = $MsiPath
try {
    $Before = Get-StartupState
    $ReparseTarget = Join-Path $Root "reparse-target"
    New-Item -ItemType Directory -Path $ReparseTarget | Out-Null
    New-Item -ItemType Junction -Path $Container -Target $ReparseTarget | Out-Null
    try {
        Assert-MsiRejected $MsiPath "$LogBase-reparse.log" "reparse Store ancestor"
        Assert-Test (-not (Test-Path -LiteralPath $Bin)) "Reparse preflight failure wrote program files."
    } finally {
        Remove-Item -LiteralPath $Container -Force
        Remove-EmptyDirectory -LiteralPath $ReparseTarget
    }
    New-Item -ItemType Directory -Path $ShortcutPath | Out-Null
    try {
        Assert-MsiRejected $MsiPath "$LogBase-shortcut.log" "unsafe existing shortcut"
        Assert-Test (-not (Test-Path -LiteralPath $Bin)) "Shortcut preflight failure wrote program files."
    } finally { Remove-Item -LiteralPath $ShortcutPath -Force }
    New-Item -ItemType Directory -Path (Join-Path $Bin "syntaur-viewer.exe") -Force | Out-Null
    try {
        Assert-MsiRejected $MsiPath "$LogBase-target.log" "bad existing program target"
        Assert-Test (-not (Test-Path -LiteralPath $StoreConfig)) "Target preflight failure created configuration."
    } finally {
        Remove-Item -LiteralPath (Join-Path $Bin "syntaur-viewer.exe") -Force
        foreach ($Directory in @($Bin, $DataRoot, $Container)) { Remove-EmptyDirectory -LiteralPath $Directory }
    }
    $Override = "INSTALLFOLDER=$(Quote-Arg (Join-Path $Root "Other"))"
    Assert-MsiRejected $MsiPath "$LogBase-override.log" "overridden INSTALLFOLDER" $Override
    Assert-Test (-not (Test-Path -LiteralPath $Bin)) "Overridden INSTALLFOLDER preflight failure wrote program files."
    Invoke-Msi /i $MsiPath "$LogBase-install.log"
    $PackageInstalled = $true
    $Names = @("viewer", "link-client-tor", "link-probe", "snowflake-client")
    foreach ($Name in $Names) { Assert-Test (Test-Path -LiteralPath (Join-Path $Bin "syntaur-$Name.exe") -PathType Leaf) "Missing installed executable: $Name" }
    $Launcher = Join-Path $Bin "SyntaurConnect.exe"
    Assert-Test (Test-Path -LiteralPath $Launcher -PathType Leaf) "Missing native launcher."
    Test-AncestorAclCompatibility -Launcher $Launcher
    Assert-Test (-not (Test-Path -LiteralPath $StoreConfig)) "MSI install created private configuration."
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $Container "Roaming"))) "MSI install created roaming state."
    $Shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($ShortcutPath)
    Assert-Test ($Shortcut.TargetPath -ceq $Launcher) "Shortcut does not target the native launcher."
    Assert-Test ($Shortcut.Arguments -ceq "") "Shortcut arguments must be empty."
    Assert-Test ($Shortcut.WorkingDirectory -ceq $Bin) "Shortcut working directory is incorrect."
    Assert-Test ($Before -ceq (Get-StartupState)) "Install changed PATH, Run, or Startup."
    foreach ($Path in $Markers.Keys) { Assert-Bytes $Path $Markers[$Path] "install" }

    $Process = Start-Native $Launcher "--initialize-only"
    Assert-Test ($Process.ExitCode -eq 0) "Native initialization failed with exit code $($Process.ExitCode)."
    Assert-Test (Test-Path -LiteralPath $StoreConfig -PathType Leaf) "Initialization did not create Store client.json."
    $InitialConfig = Get-Content -LiteralPath $StoreConfig -Raw | ConvertFrom-Json
    Assert-Test ($InitialConfig.transport_binary -ceq (Join-Path $Bin "syntaur-snowflake-client.exe")) "Initialization did not select bundled Store Snowflake."
    foreach ($Path in $Markers.Keys) { Assert-Bytes $Path $Markers[$Path] "initialization" }

    $StoreMarkers[$StoreConfig] = [Text.Encoding]::UTF8.GetBytes("private Store Tor marker")
    $StoreMarkers[(Join-Path $Container "Roaming\Syntaur\link-profile.json")] = [Text.Encoding]::UTF8.GetBytes("private Store profile marker")
    $StoreMarkers[(Join-Path $DataRoot "window-state.marker")] = [Text.Encoding]::UTF8.GetBytes("private Store window marker")
    $StoreMarkers[(Join-Path $DataRoot "link-tor\state\state.marker")] = [Text.Encoding]::UTF8.GetBytes("private Store Tor state marker")
    foreach ($Path in $StoreMarkers.Keys) { [IO.File]::WriteAllBytes($Path, $StoreMarkers[$Path]) }
    if ($UpgradeMsiPath) {
        $CurrentMsi = $UpgradeMsiPath
        Invoke-Msi /i $UpgradeMsiPath "$LogBase-upgrade.log"
        Assert-Test ($Before -ceq (Get-StartupState)) "Upgrade changed PATH, Run, or Startup."
        foreach ($Path in @($Markers.Keys) + @($StoreMarkers.Keys)) { $Expected = if ($Markers.ContainsKey($Path)) { $Markers[$Path] } else { $StoreMarkers[$Path] }; Assert-Bytes $Path $Expected "upgrade" }
    }
    Invoke-Msi /x $CurrentMsi "$LogBase-uninstall.log"
    $PackageInstalled = $false
    foreach ($Name in $Names) { Assert-Test (-not (Test-Path -LiteralPath (Join-Path $Bin "syntaur-$Name.exe"))) "Uninstall left package executable: $Name" }
    Assert-Test (-not (Test-Path -LiteralPath $Launcher)) "Uninstall left the launcher."
    Assert-Test (-not (Test-Path -LiteralPath $ShortcutPath)) "Uninstall left the shortcut."
    Assert-Test ($Before -ceq (Get-StartupState)) "Uninstall changed PATH, Run, or Startup."
    foreach ($Path in @($Markers.Keys) + @($StoreMarkers.Keys)) { $Expected = if ($Markers.ContainsKey($Path)) { $Markers[$Path] } else { $StoreMarkers[$Path] }; Assert-Bytes $Path $Expected "uninstall" }
    Write-Host "PASS: isolated native Store install, initialization, separation, preservation, and uninstall checks."
} finally {
    if ($PackageInstalled) { Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $(Quote-Arg $CurrentMsi) /qn /norestart" -Wait -WindowStyle Hidden }
    foreach ($Path in @($Markers.Keys) + @($StoreMarkers.Keys)) { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    if (($StoreMarkers.Count -eq 0) -and (Test-Path -LiteralPath $StoreConfig)) { Remove-Item -LiteralPath $StoreConfig -Force }
    $Directories = @((Join-Path $DataRoot "link-tor\state"), (Join-Path $DataRoot "link-tor\cache"), (Join-Path $DataRoot "link-tor"),
        (Join-Path $Container "Roaming\Syntaur"), (Join-Path $Container "Roaming"), $Bin, $DataRoot, $Container,
        $DirectTor, $DirectProfiles, $Root)
    foreach ($Directory in $Directories) { Remove-EmptyDirectory -LiteralPath $Directory }
}
