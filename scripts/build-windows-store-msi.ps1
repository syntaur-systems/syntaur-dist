# Pipeline scope: compatibility-channels — offline packaging from existing signed release assets.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory = $true)][string]$AssetDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$WixPath,
    [Parameter(Mandatory = $true)][string]$CosignPath,
    [string]$CscPath = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    [string]$CodeSigningCertificateThumbprint,
    [string]$SignToolPath,
    [string]$TimestampUrl,
    [switch]$DevelopmentUnsigned
)
$ErrorActionPreference = "Stop"
$ExpectedIdentity = "https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main"
$ExpectedIssuer = "https://token.actions.githubusercontent.com"
$ProductionUpgradeCode = "B0A6A5C2-87B5-5F16-9F4B-3FC46F77B701"
$DevelopmentUpgradeCode = "B0A6A5C2-87B5-5F16-9F4B-3FC46F77B702"

function Assert-NoReparsePath {
    param([Parameter(Mandatory = $true)][string]$LiteralPath, [switch]$AllowMissingLeaf)
    $Full = [IO.Path]::GetFullPath($LiteralPath)
    if ($AllowMissingLeaf -and -not (Test-Path -LiteralPath $Full)) { $Full = Split-Path -Parent $Full }
    if (-not (Test-Path -LiteralPath $Full)) { throw "Path does not exist: $Full" }
    $Item = Get-Item -LiteralPath $Full -Force
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse points are not accepted: $($Item.FullName)" }
    $Current = if ($Item.PSIsContainer) { $Item } else { $Item.Directory }
    while ($null -ne $Current) {
        if (($Current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse points are not accepted: $($Current.FullName)" }
        $Current = $Current.Parent
    }
}
function Assert-InputFile {
    param([string]$LiteralPath, [int64]$MaximumBytes = 1073741824)
    Assert-NoReparsePath -LiteralPath $LiteralPath
    $Item = Get-Item -LiteralPath $LiteralPath -Force
    if ($Item.PSIsContainer -or $Item.Length -le 0 -or $Item.Length -gt $MaximumBytes) { throw "Input is not a nonempty bounded file: $LiteralPath" }
    return $Item
}
function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList)
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "$FilePath failed with exit code $LASTEXITCODE" }
}
function Get-Sha256 { param([string]$LiteralPath) (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant() }
function Protect-Authenticode {
    param([string]$LiteralPath, [string]$Thumbprint, [string]$Tool, [string]$Timestamp)
    $Before = Get-Sha256 -LiteralPath $LiteralPath
    Invoke-Native -FilePath $Tool -ArgumentList @("sign", "/fd", "SHA256", "/sha1", $Thumbprint, "/tr", $Timestamp, "/td", "SHA256", $LiteralPath)
    $Signature = Get-AuthenticodeSignature -LiteralPath $LiteralPath
    if ($Signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $Signature.SignerCertificate.Thumbprint -ine $Thumbprint) {
        throw "Trusted Authenticode verification failed: $LiteralPath ($($Signature.Status))"
    }
    Write-Host "Signed bytes: $LiteralPath`n  original SHA256: $Before`n  final SHA256:    $((Get-Sha256 -LiteralPath $LiteralPath))"
}
function Get-AstExpression {
    param([System.Management.Automation.Language.Ast]$Node)
    $Current = $Node
    while ($true) {
        if ($Current -is [System.Management.Automation.Language.CommandExpressionAst]) { $Current = $Current.Expression; continue }
        if ($Current -is [System.Management.Automation.Language.PipelineAst] -and $Current.PipelineElements.Count -eq 1) { $Current = $Current.PipelineElements[0]; continue }
        if ($Current -is [System.Management.Automation.Language.ParenExpressionAst]) { $Current = $Current.Pipeline; continue }
        if ($Current -is [System.Management.Automation.Language.ArrayExpressionAst]) { $Current = $Current.SubExpression; continue }
        if ($Current -is [System.Management.Automation.Language.StatementBlockAst] -and $Current.Statements.Count -eq 1) { $Current = $Current.Statements[0]; continue }
        if ($Current -is [System.Management.Automation.Language.ConvertExpressionAst] -and
            $Current.Type.TypeName.FullName -ceq "ordered") { $Current = $Current.Child; continue }
        return $Current
    }
}
function Get-HashMember {
    param([System.Management.Automation.Language.HashtableAst]$Hashtable, [string]$Name)
    $Pair = @($Hashtable.KeyValuePairs | Where-Object { $_.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Item1.Value -ceq $Name })
    if ($Pair.Count -ne 1) { throw "Expected exactly one literal $Name member." }
    return Get-AstExpression $Pair[0].Item2
}
function Get-LiteralValue {
    param([System.Management.Automation.Language.Ast]$Node)
    $Literal = Get-AstExpression $Node
    if ($Literal -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $Literal -is [System.Management.Automation.Language.ConstantExpressionAst]) { return $Literal.SafeGetValue() }
    if ($Literal -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $Literal.VariablePath.UserPath -in @("true", "false")) { return $Literal.VariablePath.UserPath -ceq "true" }
    throw "Expected an exact string, constant, or Boolean literal."
}
function Get-StoreTemplate {
    param([string]$InstallerPath)
    $Tokens = $null; $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($InstallerPath, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count -ne 0) { throw "Cannot parse install.ps1." }
    $Function = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -ceq "Save-LinkTorConfiguration" }, $true)
    $Assignments = @($Function.Body.FindAll({ param($Node)
        $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $Node.Left.VariablePath.UserPath -ceq "Configuration" }, $true))
    if ($Assignments.Count -ne 1) { throw "Expected exactly one Configuration assignment." }
    $Assignment = $Assignments[0]
    $Configuration = Get-AstExpression $Assignment.Right
    if ($Configuration -isnot [System.Management.Automation.Language.HashtableAst]) { throw "Store configuration is not an ordered literal hashtable." }
    $Bundle = Get-HashMember -Hashtable $Configuration -Name "bridge_bundle"
    if ($Bundle -isnot [System.Management.Automation.Language.HashtableAst]) { throw "Bridge bundle is not a literal hashtable." }
    $LinesReference = Get-HashMember -Hashtable $Bundle -Name "bridge_lines"
    if ($LinesReference -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
        $LinesReference.VariablePath.UserPath -cne "BridgeLines") { throw "bridge_lines must reference BridgeLines exactly." }
    $LineAssignments = @($Function.Body.FindAll({ param($Node)
        $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $Node.Left.VariablePath.UserPath -ceq "BridgeLines" -and $Node.Extent.StartOffset -lt $Assignment.Extent.StartOffset }, $true))
    if ($LineAssignments.Count -ne 1) { throw "Expected exactly one preceding BridgeLines assignment." }
    $Lines = Get-AstExpression $LineAssignments[0].Right
    if ($Lines -isnot [System.Management.Automation.Language.ArrayLiteralAst] -or
        $Lines.Elements.Count -lt 1 -or $Lines.Elements.Count -gt 32) { throw "BridgeLines must be one bounded literal array." }
    $BridgeLines = @($Lines.Elements | ForEach-Object {
        $Literal = Get-AstExpression $_
        if ($Literal -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $Literal.Value.Length -gt 8192) { throw "BridgeLines must contain only bounded string literals." }
        $Literal.Value
    })
    $Schema = Get-LiteralValue (Get-HashMember -Hashtable $Configuration -Name "schema")
    $BundleSchema = Get-LiteralValue (Get-HashMember -Hashtable $Bundle -Name "schema")
    $Transport = Get-LiteralValue (Get-HashMember -Hashtable $Bundle -Name "transport")
    $Bundled = Get-LiteralValue (Get-HashMember -Hashtable $Configuration -Name "bundled_transport")
    if ($Schema -ne 2 -or $BundleSchema -ne 1 -or $Transport -cne "snowflake" -or
        ($Bundled -isnot [bool]) -or -not $Bundled) { throw "Unexpected Store configuration literals." }
    return [ordered]@{ schema = $Schema; state_dir = ""; cache_dir = "";
        bridge_bundle = [ordered]@{ schema = $BundleSchema; transport = $Transport; bridge_lines = $BridgeLines };
        transport_binary = ""; bundled_transport = $Bundled }
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallerSource = Join-Path $RepoRoot "install.ps1"
$LauncherSource = Join-Path $RepoRoot "packaging\windows-store\StoreClientLauncher.cs"
$WxsSource = Join-Path $RepoRoot "packaging\windows-store\Product.wxs"
$EulaSource = Join-Path $RepoRoot "EULA.md"
$IconSource = Join-Path $RepoRoot "assets\syntaur-icon.ico"
foreach ($File in @($InstallerSource, $LauncherSource, $WxsSource, $EulaSource, $IconSource, $WixPath, $CosignPath, $CscPath)) { Assert-InputFile -LiteralPath $File | Out-Null }
$WixVersion = (& $WixPath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $WixVersion -notmatch '^5\.0\.2(?:\+[0-9A-Za-z.-]+)?$') { throw "WiX 5.0.2 is required; reported: $WixVersion" }
if (Test-Path -LiteralPath $OutputDirectory) { throw "OutputDirectory must be new: $OutputDirectory" }
$Output = [IO.Path]::GetFullPath($OutputDirectory)
Assert-NoReparsePath -LiteralPath $Output -AllowMissingLeaf
$Assets = (Get-Item -LiteralPath $AssetDirectory -Force).FullName
Assert-NoReparsePath -LiteralPath $Assets
$Checksums = Join-Path $Assets "checksums.txt"
$Bundle = Join-Path $Assets "checksums.txt.cosign.bundle"
Assert-InputFile -LiteralPath $Checksums -MaximumBytes 1048576 | Out-Null
Assert-InputFile -LiteralPath $Bundle -MaximumBytes 16777216 | Out-Null
Invoke-Native -FilePath $CosignPath -ArgumentList @("verify-blob", "--bundle", $Bundle, "--certificate-identity", $ExpectedIdentity, "--certificate-oidc-issuer", $ExpectedIssuer, $Checksums)

$Entries = @{}
foreach ($Line in [IO.File]::ReadAllLines($Checksums)) {
    if ([string]::IsNullOrWhiteSpace($Line)) { continue }
    if ($Line -notmatch '^([0-9a-fA-F]{64})  ([^/\\]+)$') { throw "Malformed checksum entry." }
    $Name = $Matches[2]
    if ($Name -in @(".", "..") -or $Name.Contains(":") -or $Name.Contains([char]0) -or $Entries.ContainsKey($Name)) { throw "Unsafe or duplicate checksum entry: $Name" }
    $Entries[$Name] = $Matches[1].ToLowerInvariant()
}
$InstallerText = [IO.File]::ReadAllText($InstallerSource)
$VersionMatch = [regex]::Match($InstallerText, '(?m)^\$Version = "([^"]+)"$')
if (-not $VersionMatch.Success -or $VersionMatch.Groups[1].Value -cne $Version) { throw "Requested Version does not match the installer pin." }
$AssetsToStage = [ordered]@{
    "syntaur-viewer-windows-x86_64.exe" = @("syntaur-viewer.exe", "ViewerSha256")
    "syntaur-link-client-tor-windows-x86_64.exe" = @("syntaur-link-client-tor.exe", "LinkClientTorSha256")
    "syntaur-link-probe-windows-x86_64.exe" = @("syntaur-link-probe.exe", "LinkProbeSha256")
    "syntaur-snowflake-client-windows-x86_64.exe" = @("syntaur-snowflake-client.exe", "SnowflakeClientSha256")
}
$Signing = -not $DevelopmentUnsigned
if ($Signing) {
    if ($CodeSigningCertificateThumbprint -notmatch '^[0-9A-Fa-f]{40}$' -or [string]::IsNullOrWhiteSpace($SignToolPath) -or [string]::IsNullOrWhiteSpace($TimestampUrl)) {
        throw "Production requires a CurrentUser certificate thumbprint, SignToolPath, and TimestampUrl."
    }
    Assert-InputFile -LiteralPath $SignToolPath | Out-Null
    $Certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CodeSigningCertificateThumbprint"
    $Eku = @($Certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq "1.3.6.1.5.5.7.3.3" })
    if (-not $Certificate.HasPrivateKey -or $Eku.Count -ne 1 -or $Certificate.NotBefore -gt (Get-Date) -or $Certificate.NotAfter -lt (Get-Date)) { throw "The CurrentUser certificate is not a valid code-signing private key." }
}

New-Item -ItemType Directory -Path $Output | Out-Null
$Staging = Join-Path $Output "staging"
New-Item -ItemType Directory -Path $Staging | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Staging "assets") | Out-Null
$SignedPaths = @()
foreach ($OriginalName in $AssetsToStage.Keys) {
    if (-not $Entries.ContainsKey($OriginalName)) { throw "Missing authenticated checksum: $OriginalName" }
    $Source = Join-Path $Assets $OriginalName
    Assert-InputFile -LiteralPath $Source | Out-Null
    if ((Get-Sha256 -LiteralPath $Source) -cne $Entries[$OriginalName]) { throw "Authenticated checksum mismatch: $OriginalName" }
    $PinMatch = [regex]::Match($InstallerText, '(?m)^\$' + $AssetsToStage[$OriginalName][1] + ' = "([0-9a-f]{64})"$')
    if (-not $PinMatch.Success -or $PinMatch.Groups[1].Value -cne $Entries[$OriginalName]) { throw "Installer pin mismatch: $OriginalName" }
    $Destination = Join-Path $Staging $AssetsToStage[$OriginalName][0]
    Copy-Item -LiteralPath $Source -Destination $Destination
    if ((Get-Sha256 -LiteralPath $Destination) -cne $Entries[$OriginalName]) { throw "Staged copy checksum mismatch: $OriginalName" }
    $SignedPaths += $Destination
}
$Launcher = Join-Path $Staging "SyntaurConnect.exe"
Invoke-Native -FilePath $CscPath -ArgumentList @("/nologo", "/target:winexe", "/platform:x64", "/optimize+", "/warn:4", "/warnaserror+", "/reference:System.Web.Extensions.dll", "/reference:System.Windows.Forms.dll", "/out:$Launcher", $LauncherSource)
$SignedPaths += $Launcher
$Template = Get-StoreTemplate -InstallerPath $InstallerSource
[IO.File]::WriteAllText((Join-Path $Staging "store-client-template.json"), ($Template | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
Copy-Item -LiteralPath $EulaSource -Destination (Join-Path $Staging "EULA.md")
Copy-Item -LiteralPath $IconSource -Destination (Join-Path $Staging "assets\syntaur-icon.ico")
if ($Signing) { foreach ($Path in $SignedPaths) { Protect-Authenticode -LiteralPath $Path -Thumbprint $CodeSigningCertificateThumbprint -Tool $SignToolPath -Timestamp $TimestampUrl } }
$ProductName = if ($Signing) { "Syntaur Connect" } else { "Syntaur Connect DEVELOPMENT ONLY" }
$UpgradeCode = if ($Signing) { $ProductionUpgradeCode } else { $DevelopmentUpgradeCode }
$FileName = if ($Signing) { "Syntaur-Connect-$Version.msi" } else { "Syntaur-Connect-$Version-DEVELOPMENT-ONLY.msi" }
$Msi = Join-Path $Output $FileName
Invoke-Native -FilePath $WixPath -ArgumentList @("build", $WxsSource, "-arch", "x64", "-d", "ProductVersion=$Version", "-d", "ProductName=$ProductName", "-d", "UpgradeCode=$UpgradeCode", "-d", "StagingDirectory=$Staging\", "-out", $Msi)
Assert-InputFile -LiteralPath $Msi | Out-Null
if ($Signing) {
    Protect-Authenticode -LiteralPath $Msi -Thumbprint $CodeSigningCertificateThumbprint -Tool $SignToolPath -Timestamp $TimestampUrl
    Write-Host "Signed per-user MSI created: $Msi"
} else { Write-Warning "DEVELOPMENT ONLY unsigned lifecycle prototype created (not Store-ready): $Msi" }
Write-Host "Original release assets and authenticated checksums were not modified. Final hashes apply only to staged derivative bytes."
