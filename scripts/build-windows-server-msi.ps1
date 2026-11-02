# Pipeline scope: compatibility-channels — standard Windows SERVER development
# packaging of retained native outputs; no release dispatch or new authority.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory = $true)][string]$InputDirectory,
    [Parameter(Mandatory = $true)][string]$InputHashes,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$WixPath,
    [ValidatePattern('^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$')][string]$DevelopmentProductCode,
    [switch]$DevelopmentUnsigned,
    [switch]$SignedCandidate,
    [string]$SigningMetadata,
    [string]$SignToolPath,
    [string]$DlibPath,
    [switch]$AcceptWix7Eula
)
$ErrorActionPreference = 'Stop'
if (!$DevelopmentUnsigned -and !$SignedCandidate) {
    throw 'This development builder cannot produce a public package. Existing signed-release asset verification and Authenticode integration remain required.'
}
if ($DevelopmentUnsigned -and ($SignedCandidate -or $SigningMetadata -or $SignToolPath -or $DlibPath -or $AcceptWix7Eula)) {
    throw 'Unsigned development and signed-candidate options cannot be combined.'
}
if ($SignedCandidate -and (!$SigningMetadata -or !$SignToolPath -or !$DlibPath -or !$AcceptWix7Eula)) {
    throw 'A signed candidate requires signing metadata, SignTool, the Microsoft dlib, and explicit WiX 7 EULA acceptance.'
}
function Assert-LocalPath {
    param([string]$LiteralPath, [switch]$AllowMissingLeaf)
    $full = [IO.Path]::GetFullPath($LiteralPath)
    if ($full.Length -lt 3 -or $full[1] -ne ':' -or $full[2] -ne '\') { throw 'A local Windows path is required.' }
    if ($AllowMissingLeaf -and !(Test-Path -LiteralPath $full)) { $full = Split-Path -Parent $full }
    $item = Get-Item -LiteralPath $full -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse paths are refused.' }
        $item = if ($item.PSIsContainer) { $item.Parent } else { $item.Directory }
    }
}
function Get-Hash { param([string]$LiteralPath) (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant() }
function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList)
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "Native package build failed with exit code $LASTEXITCODE." }
}
function ConvertTo-LicenseRtf {
    param([string]$Text)
    $rtf = New-Object Text.StringBuilder
    [void]$rtf.Append('{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\viewkind4\uc1\pard\f0\fs18 ')
    foreach ($unit in $Text.ToCharArray()) {
        $code = [int]$unit
        if ($unit -eq '\' -or $unit -eq '{' -or $unit -eq '}') { [void]$rtf.Append('\').Append($unit) }
        elseif ($code -eq 10) { [void]$rtf.Append('\par ') }
        elseif ($code -eq 13) { continue }
        elseif ($code -eq 9) { [void]$rtf.Append('\tab ') }
        elseif ($code -ge 32 -and $code -le 126) { [void]$rtf.Append($unit) }
        else {
            if ($code -gt 32767) { $code -= 65536 }
            [void]$rtf.Append('\u').Append($code).Append('?')
        }
    }
    [void]$rtf.Append('}')
    return $rtf.ToString()
}
$root = Split-Path -Parent $PSScriptRoot
$wxs = Join-Path $root 'packaging\windows-server\Product.wxs'
$ui = Join-Path $root 'packaging\windows-server\SetupUI.wxs'
foreach ($path in @($InputDirectory, $InputHashes, $WixPath, $wxs, $ui)) { Assert-LocalPath $path }
if ($SignedCandidate) {
    $signingFunctions = Join-Path $root 'packaging\windows-server\ArtifactSigning.ps1'
    foreach ($path in @($SigningMetadata, $SignToolPath, $DlibPath, $signingFunctions)) { Assert-LocalPath $path }
    . $signingFunctions
    $metadata = Read-SyntaurArtifactSigningMetadata -LiteralPath $SigningMetadata
}
if ((Get-Item -LiteralPath $InputHashes).Length -gt 16384) { throw 'Input hash list exceeds its bound.' }
$hashes = Get-Content -Raw -LiteralPath $InputHashes | ConvertFrom-Json
$expected = @('ServerLauncher.exe', 'InstallerProvisioner.exe', 'syntaur.exe', 'syntaur-viewer.exe',
    'syntaur-link-tor.exe', 'syntaur-link-client-tor.exe', 'syntaur-link-probe.exe',
    'syntaur-snowflake-client.exe', 'EULA.md', 'assets\syntaur-icon.ico')
if (@($hashes.PSObject.Properties).Count -ne $expected.Count) { throw 'Unexpected development input set.' }
foreach ($name in $expected) {
    $entry = @($hashes.PSObject.Properties | Where-Object { $_.Name -ceq $name })
    if ($entry.Count -ne 1 -or $entry[0].Value -cnotmatch '^[a-f0-9]{64}$') { throw 'Missing exact development input hash.' }
    $path = Join-Path $InputDirectory $name
    Assert-LocalPath $path
    $file = Get-Item -LiteralPath $path -Force
    if ($file.PSIsContainer -or $file.Length -le 0 -or $file.Length -gt 1GB -or (Get-Hash $path) -cne $entry[0].Value) {
        throw 'Development input does not match its captured bytes.'
    }
}
$wixVersion = (& $WixPath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'WiX version query failed.' }
if ($SignedCandidate) {
    if ($wixVersion -notmatch '^7\.0\.1(?:\+[0-9A-Za-z.-]+)?$') { throw 'Signed candidates require WiX 7.0.1.' }
} elseif ($wixVersion -notmatch '^5\.0\.2(?:\+[0-9A-Za-z.-]+)?$') {
    throw 'Unsigned development packages require the cached WiX 5.0.2.'
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory must be new.' }
Assert-LocalPath $OutputDirectory -AllowMissingLeaf
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (!$DevelopmentProductCode) { $DevelopmentProductCode = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}' }
else { $DevelopmentProductCode = $DevelopmentProductCode.ToUpperInvariant() }
New-Item -ItemType Directory -Path $output | Out-Null
$stage = Join-Path $output 'staging'
New-Item -ItemType Directory -Path (Join-Path $stage 'assets') -Force | Out-Null
foreach ($name in $expected) {
    $destination = Join-Path $stage $name
    Copy-Item -LiteralPath (Join-Path $InputDirectory $name) -Destination $destination
    if ((Get-Hash $destination) -cne $hashes.$name) { throw 'Staged development input differs.' }
}
$signedInputHashes = $null
if ($SignedCandidate) {
    $metadataPath = Join-Path $stage 'artifact-signing-metadata.json'
    $metadata | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    $runtimeNames = @($expected | Where-Object { $_.EndsWith('.exe', [StringComparison]::Ordinal) })
    $runtimePaths = @($runtimeNames | ForEach-Object { Join-Path $stage $_ })
    Invoke-SyntaurArtifactSigning -LiteralPaths $runtimePaths -SignToolPath $SignToolPath -DlibPath $DlibPath -MetadataPath $metadataPath
    $signedInputHashes = [ordered]@{}
    foreach ($name in $runtimeNames) { $signedInputHashes[$name] = Get-Hash (Join-Path $stage $name) }
}
$licenseRtf = Join-Path $stage 'EULA.rtf'
$licenseText = [IO.File]::ReadAllText((Join-Path $stage 'EULA.md'), [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($licenseRtf, (ConvertTo-LicenseRtf $licenseText), [Text.Encoding]::ASCII)
$suffix = if ($SignedCandidate) { 'SIGNED-CANDIDATE' } else { 'DEVELOPMENT-ONLY' }
$productName = if ($SignedCandidate) { 'Syntaur SIGNED TEST CANDIDATE' } else { 'Syntaur DEVELOPMENT ONLY' }
$msi = Join-Path $output ("Syntaur-Server-$Version-$suffix.msi")
$wixArguments = @('build', $wxs, $ui, '-arch', 'x64', '-wx',
    '-d', "ProductVersion=$Version", '-d', "ProductName=$productName",
    '-d', 'UpgradeCode=05FAEEC7-80A8-4B12-B6DB-28528B7EEB37',
    '-d', "ProductCode=$DevelopmentProductCode",
    '-d', "StagingDirectory=$stage\", '-out', $msi)
if ($SignedCandidate) { $wixArguments += @('-acceptEula', 'wix7', '-nohardlinks') }
Invoke-Native -FilePath $WixPath -ArgumentList $wixArguments
if ($SignedCandidate) {
    foreach ($name in $runtimeNames) {
        if ((Get-Hash (Join-Path $stage $name)) -cne $signedInputHashes[$name]) { throw 'A signed payload changed during packaging.' }
    }
    Invoke-SyntaurArtifactSigning -LiteralPaths @($msi) -SignToolPath $SignToolPath -DlibPath $DlibPath -MetadataPath $metadataPath
    Remove-Item -LiteralPath $metadataPath
}
$result = [ordered]@{
    development_only = !$SignedCandidate; version = $Version; msi_sha256 = (Get-Hash $msi)
    input_sha256 = $hashes; package_source_sha256 = (Get-Hash $wxs)
    setup_ui_sha256 = (Get-Hash $ui); derived_license_rtf_sha256 = (Get-Hash $licenseRtf)
    signed = [bool]$SignedCandidate; signed_input_sha256 = $signedInputHashes
    store_ready = $false; public_release = $false; existing_data_in_package = $false
    development_product_code = $DevelopmentProductCode
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'build-result.json') -Encoding UTF8
Write-Output "$suffix SERVER candidate built. No publication, certification, or installation performed."
