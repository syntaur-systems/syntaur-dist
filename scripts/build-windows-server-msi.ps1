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
    [switch]$PublicRelease,
    [string]$SigningMetadata,
    [string]$SignToolPath,
    [string]$DlibPath,
    [switch]$AcceptWix7Eula
)
$ErrorActionPreference = 'Stop'
if (!$DevelopmentUnsigned -and !$SignedCandidate -and !$PublicRelease) {
    throw 'This development builder cannot produce a public package. Existing signed-release asset verification and Authenticode integration remain required.'
}
if ($DevelopmentUnsigned -and ($SignedCandidate -or $PublicRelease -or $SigningMetadata -or $SignToolPath -or $DlibPath -or $AcceptWix7Eula)) {
    throw 'Unsigned development and signed-candidate options cannot be combined.'
}
if ($SignedCandidate -and (!$SigningMetadata -or !$SignToolPath -or !$DlibPath -or !$AcceptWix7Eula)) {
    throw 'A signed candidate requires signing metadata, SignTool, the Microsoft dlib, and explicit WiX 7 EULA acceptance.'
}
if ($PublicRelease -and ($SignedCandidate -or $DevelopmentProductCode)) {
    throw 'Public releases cannot use candidate mode or a development product identity.'
}
if ($PublicRelease -and (!$SigningMetadata -or !$SignToolPath -or !$DlibPath -or !$AcceptWix7Eula)) {
    throw 'A public release requires signing metadata, SignTool, the Microsoft dlib, and explicit WiX 7 EULA acceptance.'
}
$trustedSigning = $SignedCandidate -or $PublicRelease
function Assert-SyntaurPublicReleaseContext {
    param([string]$Root, [string]$Version)
    if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'syntaur-systems/syntaur-dist' -or
        $env:GITHUB_REF -cne 'refs/heads/main') { throw 'Public release requires protected main CI.' }
    if ($env:GITHUB_RUN_ATTEMPT -cne '1') { throw 'Public release requires its original workflow attempt.' }
    if ($env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]{0,19}$' -or $env:REL_VERSION -cne $Version -or
        $env:SRC_REF -cne ('v' + $Version)) { throw 'Invalid public release identity.' }
    foreach ($commit in @($env:SRC_COMMIT, $env:ENGINE_COMMIT, $env:DIST_COMMIT)) {
        if ($commit -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid public release identity.' }
    }
    $head = & git -C $Root rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $head -cne $env:DIST_COMMIT -or $env:GITHUB_SHA -cne $env:DIST_COMMIT) {
        throw 'Public release source tuple does not match its checkout.'
    }
    $status = & git -C $Root status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0 -or $status) { throw 'Public release checkout must be clean.' }
    $parts = @('syntaur-release-operation-v2', $Version, ('v' + $Version), $env:SRC_COMMIT,
        $env:ENGINE_COMMIT, $env:DIST_COMMIT)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join [char]0) + [char]0)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $correlation = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($env:RELEASE_CORRELATION -cne $correlation) { throw 'Public release correlation mismatch.' }
}
function Assert-LocalPath {
    param([string]$LiteralPath, [switch]$AllowMissingLeaf)
    $full = [IO.Path]::GetFullPath($LiteralPath)
    if ($full.Length -lt 3 -or $full[1] -ne ':' -or $full[2] -ne '\') { throw 'A local Windows path is required.' }
    if ($AllowMissingLeaf -and !(Test-Path -LiteralPath $full)) { $full = Split-Path -Parent $full }
    $item = Get-Item -LiteralPath $full -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse paths are refused.' }
        $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
    }
}
function Get-Hash { param([string]$LiteralPath) (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-MicrosoftRuntimeSignature {
    param([string]$LiteralPath)
    $signature = Get-AuthenticodeSignature -LiteralPath $LiteralPath
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)' -or
        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -cnotin
            @('Microsoft Windows', 'Microsoft Windows Software Compatibility Publisher', 'Microsoft Corporation')) {
        throw 'The bundled C++ runtime must retain a valid Microsoft publisher signature.'
    }
}
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
if ($PublicRelease) { Assert-SyntaurPublicReleaseContext -Root $root -Version $Version }
$wxs = Join-Path $root 'packaging\windows-server\Product.wxs'
$ui = Join-Path $root 'packaging\windows-server\SetupUI.wxs'
foreach ($path in @($InputDirectory, $InputHashes, $WixPath, $wxs, $ui)) { Assert-LocalPath $path }
if ($trustedSigning) {
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
$microsoftRuntime = @('concrt140.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
    'msvcp140_atomic_wait.dll', 'msvcp140_codecvt_ids.dll', 'vccorlib140.dll',
    'vcruntime140.dll', 'vcruntime140_1.dll', 'vcruntime140_threads.dll')
$expected += $microsoftRuntime
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
    if ($microsoftRuntime -ccontains $name) { Assert-MicrosoftRuntimeSignature $path }
}
$wixVersion = (& $WixPath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'WiX version query failed.' }
if ($trustedSigning) {
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
if ($trustedSigning) {
    $metadataPath = Join-Path $stage 'artifact-signing-metadata.json'
    Write-SyntaurArtifactSigningMetadata -Metadata $metadata -LiteralPath $metadataPath
    $runtimeNames = @($expected | Where-Object { $_.EndsWith('.exe', [StringComparison]::Ordinal) })
    $runtimePaths = @($runtimeNames | ForEach-Object { Join-Path $stage $_ })
    Invoke-SyntaurArtifactSigning -LiteralPaths $runtimePaths -SignToolPath $SignToolPath -DlibPath $DlibPath -MetadataPath $metadataPath
    $signedInputHashes = [ordered]@{}
    foreach ($name in $runtimeNames) { $signedInputHashes[$name] = Get-Hash (Join-Path $stage $name) }
}
$licenseRtf = Join-Path $stage 'EULA.rtf'
$licenseText = [IO.File]::ReadAllText((Join-Path $stage 'EULA.md'), [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($licenseRtf, (ConvertTo-LicenseRtf $licenseText), [Text.Encoding]::ASCII)
$suffix = if ($PublicRelease) { 'PUBLIC-RELEASE' } elseif ($SignedCandidate) { 'SIGNED-CANDIDATE' } else { 'DEVELOPMENT-ONLY' }
$productName = if ($PublicRelease) { 'Syntaur' } elseif ($SignedCandidate) { 'Syntaur SIGNED TEST CANDIDATE' } else { 'Syntaur DEVELOPMENT ONLY' }
$upgradeCode = if ($PublicRelease) { '3C057823-F0A2-4385-813F-9D654747D7DF' } else { '05FAEEC7-80A8-4B12-B6DB-28528B7EEB37' }
$msiName = if ($PublicRelease) { 'syntaur-server-windows-x86_64.msi' } else { "Syntaur-Server-$Version-$suffix.msi" }
$msi = Join-Path $output $msiName
$wixArguments = @('build', $wxs, $ui, '-arch', 'x64', '-wx',
    '-d', "ProductVersion=$Version", '-d', "ProductName=$productName",
    '-d', "UpgradeCode=$upgradeCode",
    '-d', "ProductCode=$DevelopmentProductCode",
    '-d', "StagingDirectory=$stage\", '-out', $msi)
if ($trustedSigning) { $wixArguments += @('-acceptEula', 'wix7', '-nohardlinks') }
Invoke-Native -FilePath $WixPath -ArgumentList $wixArguments
if ($trustedSigning) {
    foreach ($name in $runtimeNames) {
        if ((Get-Hash (Join-Path $stage $name)) -cne $signedInputHashes[$name]) { throw 'A signed payload changed during packaging.' }
    }
    Invoke-SyntaurArtifactSigning -LiteralPaths @($msi) -SignToolPath $SignToolPath -DlibPath $DlibPath -MetadataPath $metadataPath
    Remove-Item -LiteralPath $metadataPath
}
foreach ($name in $expected) {
    if (!$name.EndsWith('.exe', [StringComparison]::Ordinal) -and
        (Get-Hash (Join-Path $stage $name)) -cne $hashes.$name) {
        throw 'An unsigned-by-Syntaur package member changed during packaging.'
    }
}
$result = [ordered]@{
    development_only = !$trustedSigning; version = $Version; msi_sha256 = (Get-Hash $msi)
    input_sha256 = $hashes; package_source_sha256 = (Get-Hash $wxs)
    setup_ui_sha256 = (Get-Hash $ui); derived_license_rtf_sha256 = (Get-Hash $licenseRtf)
    signed = [bool]$trustedSigning; signed_input_sha256 = $signedInputHashes
    store_ready = $false; public_release = [bool]$PublicRelease; existing_data_in_package = $false
    product_code = $DevelopmentProductCode; upgrade_code = $upgradeCode; package_mode = $suffix
    development_product_code = $(if (!$PublicRelease) { $DevelopmentProductCode } else { $null })
}
if ($PublicRelease) {
    $result.release_identity = [ordered]@{ source_commit = $env:SRC_COMMIT; engine_commit = $env:ENGINE_COMMIT
        dist_commit = $env:DIST_COMMIT; correlation = $env:RELEASE_CORRELATION
        run_id = $env:GITHUB_RUN_ID; run_attempt = $env:GITHUB_RUN_ATTEMPT }
}
[IO.File]::WriteAllText((Join-Path $output 'build-result.json'), ($result | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
Write-Output "$suffix SERVER candidate built. No publication, certification, or installation performed."
