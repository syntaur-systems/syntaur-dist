# Pipeline scope: compatibility-channels — dependency-free unit tests for ArtifactSigning helper and builder preflight
# Note: Tests run in Windows PowerShell 5.1 without Pester, external tools, or cryptographic dependencies.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Write-Output '=== SYNTAUR ARTIFACT SIGNING & BUILDER PREFLIGHT TEST SUITE ==='
Write-Output 'Notice: Mocked verification only. Tests are synthetic and convey no cryptographic acceptance.'

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$artifactSigningScript = Join-Path $scriptRoot 'ArtifactSigning.ps1'
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$builderScript = Join-Path $repoRoot 'scripts\build-windows-server-msi.ps1'

if (!(Test-Path -LiteralPath $artifactSigningScript)) {
    throw "ArtifactSigning.ps1 not found at $artifactSigningScript"
}

. $artifactSigningScript

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][string]$ExpectedMessageSubstring,
        [Parameter(Mandatory = $true)][string]$TestName
    )
    $threw = $false
    try {
        & $ScriptBlock
    } catch {
        $threw = $true
        if ($_.Exception.Message -notlike "*$ExpectedMessageSubstring*") {
            throw "[$TestName] Expected exception containing '$ExpectedMessageSubstring' but got: '$($_.Exception.Message)'"
        }
    }
    if (!$threw) {
        throw "[$TestName] Expected exception containing '$ExpectedMessageSubstring' but block succeeded."
    }
    Write-Output "  PASS: $TestName"
}

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("SyntaurSignTest_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Backup existing functions/cmdlets if present
$origAuthenticodeCmd = Get-Command -Name Get-AuthenticodeSignature -ErrorAction SilentlyContinue
$origSignToolCmd = Get-Command -Name Invoke-SyntaurSigningTool -ErrorAction SilentlyContinue

try {
    # -------------------------------------------------------------
    # 1. Read-SyntaurArtifactSigningMetadata tests
    # -------------------------------------------------------------
    Write-Output 'Running Read-SyntaurArtifactSigningMetadata tests...'

    # Valid metadata test
    $validMetaPath = Join-Path $tempDir 'valid-metadata.json'
    @{
        Endpoint = 'https://wus2.codesigning.azure.net/'
        CodeSigningAccountName = 'syntaurenterprisesllc'
        CertificateProfileName = 'ReleaseProfile-2026'
    } | ConvertTo-Json | Set-Content -LiteralPath $validMetaPath -Encoding UTF8

    $parsed = Read-SyntaurArtifactSigningMetadata -LiteralPath $validMetaPath
    if ($parsed.Endpoint -ne 'https://wus2.codesigning.azure.net/' -or
        $parsed.CodeSigningAccountName -ne 'syntaurenterprisesllc' -or
        $parsed.CertificateProfileName -ne 'ReleaseProfile-2026') {
        throw 'Valid metadata properties did not match expected values.'
    }

    # Verify 9 excluded credentials and AzureCliCredential not excluded
    $expectedExcluded = @(
        'EnvironmentCredential', 'WorkloadIdentityCredential',
        'ManagedIdentityCredential', 'SharedTokenCacheCredential',
        'VisualStudioCredential', 'VisualStudioCodeCredential',
        'AzurePowerShellCredential', 'AzureDeveloperCliCredential',
        'InteractiveBrowserCredential'
    )
    if ($parsed.ExcludeCredentials.Count -ne 9) {
        throw "Expected 9 excluded credentials, got $($parsed.ExcludeCredentials.Count)"
    }
    foreach ($cred in $expectedExcluded) {
        if ($parsed.ExcludeCredentials -notcontains $cred) {
            throw "Expected excluded credential '$cred' missing from ExcludeCredentials."
        }
    }
    if ($parsed.ExcludeCredentials -contains 'AzureCliCredential') {
        throw 'AzureCliCredential must NOT be in ExcludeCredentials list.'
    }
    Write-Output '  PASS: Valid metadata reads exactly 3 fields and populates 9 excluded credentials (AzureCliCredential retained)'

    # Real serialization through the same writer used by the builder.
    $writtenMetaPath = Join-Path $tempDir 'written-metadata.json'
    Write-SyntaurArtifactSigningMetadata -Metadata $parsed -LiteralPath $writtenMetaPath
    $writtenBytes = [IO.File]::ReadAllBytes($writtenMetaPath)
    if ($writtenBytes.Length -ge 3 -and $writtenBytes[0] -eq 0xEF -and $writtenBytes[1] -eq 0xBB -and $writtenBytes[2] -eq 0xBF) {
        throw 'Written signing metadata must not start with a UTF-8 BOM.'
    }
    $writtenText = (New-Object Text.UTF8Encoding($false)).GetString($writtenBytes)
    if (!$writtenText.TrimStart().StartsWith('{')) {
        throw 'Written signing metadata must start with a JSON object.'
    }
    $writtenValue = $writtenText | ConvertFrom-Json
    if ($writtenValue.Endpoint -cne 'https://wus2.codesigning.azure.net/' -or
        $writtenValue.CodeSigningAccountName -cne 'syntaurenterprisesllc' -or
        $writtenValue.CertificateProfileName -cne 'ReleaseProfile-2026') {
        throw 'Written signing metadata public fields did not round-trip.'
    }
    if (@($writtenValue.ExcludeCredentials).Count -ne 9) {
        throw 'Written signing metadata must preserve 9 excluded credentials.'
    }
    foreach ($cred in $expectedExcluded) {
        if (@($writtenValue.ExcludeCredentials) -notcontains $cred) {
            throw "Written signing metadata lost excluded credential '$cred'."
        }
    }
    Write-Output '  PASS: Written metadata is BOM-less UTF-8 JSON with public fields and 9 exclusions preserved'

    # Extra public field rejected
    $extraFieldMeta = Join-Path $tempDir 'extra-field.json'
    @{
        Endpoint = 'https://wus2.codesigning.azure.net/'
        CodeSigningAccountName = 'syntaurenterprisesllc'
        CertificateProfileName = 'ReleaseProfile-2026'
        ExtraField = 'unexpected'
    } | ConvertTo-Json | Set-Content -LiteralPath $extraFieldMeta -Encoding UTF8

    Assert-Throws -TestName 'Reject extra metadata field' `
        -ScriptBlock { Read-SyntaurArtifactSigningMetadata -LiteralPath $extraFieldMeta } `
        -ExpectedMessageSubstring 'Signing metadata must contain only the three public profile fields.'

    # Missing public field rejected
    $missingFieldMeta = Join-Path $tempDir 'missing-field.json'
    @{
        Endpoint = 'https://wus2.codesigning.azure.net/'
        CodeSigningAccountName = 'syntaurenterprisesllc'
    } | ConvertTo-Json | Set-Content -LiteralPath $missingFieldMeta -Encoding UTF8

    Assert-Throws -TestName 'Reject missing metadata field' `
        -ScriptBlock { Read-SyntaurArtifactSigningMetadata -LiteralPath $missingFieldMeta } `
        -ExpectedMessageSubstring 'Signing metadata must contain only the three public profile fields.'

    # Rejection of credential field in metadata
    $credFieldMeta = Join-Path $tempDir 'credential-field.json'
    @{
        Endpoint = 'https://wus2.codesigning.azure.net/'
        CodeSigningAccountName = 'syntaurenterprisesllc'
        CertificateProfileName = 'ReleaseProfile-2026'
        ClientSecret = 'fake-secret'
    } | ConvertTo-Json | Set-Content -LiteralPath $credFieldMeta -Encoding UTF8

    Assert-Throws -TestName 'Reject metadata containing credential/secret field' `
        -ScriptBlock { Read-SyntaurArtifactSigningMetadata -LiteralPath $credFieldMeta } `
        -ExpectedMessageSubstring 'Signing metadata must contain only the three public profile fields.'

    # Rejection of wrong endpoint
    $badEndpointMeta = Join-Path $tempDir 'bad-endpoint.json'
    @{
        Endpoint = 'https://eus.codesigning.azure.net/'
        CodeSigningAccountName = 'syntaurenterprisesllc'
        CertificateProfileName = 'ReleaseProfile-2026'
    } | ConvertTo-Json | Set-Content -LiteralPath $badEndpointMeta -Encoding UTF8

    Assert-Throws -TestName 'Reject invalid endpoint' `
        -ScriptBlock { Read-SyntaurArtifactSigningMetadata -LiteralPath $badEndpointMeta } `
        -ExpectedMessageSubstring 'Signing metadata does not select the Syntaur signing account.'

    # Rejection of wrong account
    $badAccountMeta = Join-Path $tempDir 'bad-account.json'
    @{
        Endpoint = 'https://wus2.codesigning.azure.net/'
        CodeSigningAccountName = 'otheraccount'
        CertificateProfileName = 'ReleaseProfile-2026'
    } | ConvertTo-Json | Set-Content -LiteralPath $badAccountMeta -Encoding UTF8

    Assert-Throws -TestName 'Reject invalid account' `
        -ScriptBlock { Read-SyntaurArtifactSigningMetadata -LiteralPath $badAccountMeta } `
        -ExpectedMessageSubstring 'Signing metadata does not select the Syntaur signing account.'

    # Rejection of invalid profile regex
    $badProfileMeta = Join-Path $tempDir 'bad-profile.json'
    @{
        Endpoint = 'https://wus2.codesigning.azure.net/'
        CodeSigningAccountName = 'syntaurenterprisesllc'
        CertificateProfileName = 'Invalid Profile Name!'
    } | ConvertTo-Json | Set-Content -LiteralPath $badProfileMeta -Encoding UTF8

    Assert-Throws -TestName 'Reject invalid profile name' `
        -ScriptBlock { Read-SyntaurArtifactSigningMetadata -LiteralPath $badProfileMeta } `
        -ExpectedMessageSubstring 'Signing metadata does not select the Syntaur signing account.'

    # -------------------------------------------------------------
    # 2. Invoke-SyntaurArtifactSigning input validation tests
    # -------------------------------------------------------------
    Write-Output 'Running Invoke-SyntaurArtifactSigning input validation tests...'

    # 0 items rejected
    Assert-Throws -TestName 'Reject empty LiteralPaths' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths @() -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'empty array'

    # 9 items rejected
    $nineFiles = @(1..9 | ForEach-Object { "C:\staged\file$_.exe" })
    Assert-Throws -TestName 'Reject > 8 LiteralPaths' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths $nineFiles -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'Unexpected signing input count.'

    # Duplicate paths rejected before any signing
    $dupFiles = @('C:\staged\file1.exe', 'C:\staged\file2.exe', 'C:\staged\file1.exe')
    Assert-Throws -TestName 'Reject duplicate LiteralPaths' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths $dupFiles -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'Duplicate signing input.'

    # -------------------------------------------------------------
    # 3. Exact sign -> verify order, args, and failure stops
    # -------------------------------------------------------------
    Write-Output 'Running signing sequence and verification tests...'

    # Helper mock certificate object
    function New-MockCert {
        param([string]$SimpleName)
        $cert = New-Object -TypeName PSObject
        $cert | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value {
            param($nameType, $forIssuer)
            return $this.SubjectSimpleName
        } -Force
        $cert | Add-Member -MemberType NoteProperty -Name SubjectSimpleName -Value $SimpleName
        return $cert
    }

    # Tracking mocks for successful multi-file signing
    $global:SignToolCalls = New-Object System.Collections.ArrayList
    $global:AuthenticodeCalls = New-Object System.Collections.ArrayList
    $global:MockAuthenticodeStatus = 'Valid'
    $global:MockSignerName = 'SYNTAUR ENTERPRISES LLC'
    $global:MockHasTimestamp = $true
    $global:MockSignToolFailOnCount = 0

    function Invoke-SyntaurSigningTool {
        param([string]$SignToolPath, [string[]]$ArgumentList)
        [void]$global:SignToolCalls.Add([pscustomobject]@{
            SignToolPath = $SignToolPath
            ArgumentList = $ArgumentList
        })
        if ($global:MockSignToolFailOnCount -gt 0 -and $global:SignToolCalls.Count -ge $global:MockSignToolFailOnCount) {
            throw "SignTool failed with exit code 1. No automatic retry was attempted."
        }
    }

    function Get-AuthenticodeSignature {
        param([string]$LiteralPath)
        [void]$global:AuthenticodeCalls.Add($LiteralPath)
        $signer = if ($null -ne $global:MockSignerName) { New-MockCert -SimpleName $global:MockSignerName } else { $null }
        $ts = if ($global:MockHasTimestamp) { New-MockCert -SimpleName 'Microsoft Time-Stamp' } else { $null }
        return [pscustomobject]@{
            Status = $global:MockAuthenticodeStatus
            SignerCertificate = $signer
            TimeStamperCertificate = $ts
            Path = $LiteralPath
        }
    }

    $filesToSign = @('C:\stage\app1.exe', 'C:\stage\app2.exe')
    $global:SignToolCalls.Clear()
    $global:AuthenticodeCalls.Clear()
    $global:MockAuthenticodeStatus = 'Valid'
    $global:MockSignerName = 'SYNTAUR ENTERPRISES LLC'
    $global:MockHasTimestamp = $true
    $global:MockSignToolFailOnCount = 0

    Invoke-SyntaurArtifactSigning -LiteralPaths $filesToSign `
        -SignToolPath 'C:\tools\signtool.exe' `
        -DlibPath 'C:\tools\dlib.dll' `
        -MetadataPath $validMetaPath

    # Verify per-file order: sign file 1, verify file 1, sign file 2, verify file 2
    if ($global:SignToolCalls.Count -ne 4) {
        throw "Expected 4 SignTool invocations (2 files x [sign, verify]), got $($global:SignToolCalls.Count)"
    }
    # Call 0: sign file 1
    $c0 = $global:SignToolCalls[0]
    $expectedSignArgs1 = @('sign', '/fd', 'SHA256', '/tr', 'http://timestamp.acs.microsoft.com/', '/td', 'SHA256', '/dlib', 'C:\tools\dlib.dll', '/dmdf', $validMetaPath, 'C:\stage\app1.exe')
    if (($c0.ArgumentList -join ' ') -ne ($expectedSignArgs1 -join ' ')) {
        throw "First file sign args mismatch: $(($c0.ArgumentList -join ' '))"
    }
    # Call 1: verify file 1
    $c1 = $global:SignToolCalls[1]
    $expectedVerifyArgs1 = @('verify', '/pa', '/all', '/tw', 'C:\stage\app1.exe')
    if (($c1.ArgumentList -join ' ') -ne ($expectedVerifyArgs1 -join ' ')) {
        throw "First file verify args mismatch: $(($c1.ArgumentList -join ' '))"
    }
    # Call 2: sign file 2
    $c2 = $global:SignToolCalls[2]
    $expectedSignArgs2 = @('sign', '/fd', 'SHA256', '/tr', 'http://timestamp.acs.microsoft.com/', '/td', 'SHA256', '/dlib', 'C:\tools\dlib.dll', '/dmdf', $validMetaPath, 'C:\stage\app2.exe')
    if (($c2.ArgumentList -join ' ') -ne ($expectedSignArgs2 -join ' ')) {
        throw "Second file sign args mismatch: $(($c2.ArgumentList -join ' '))"
    }
    # Call 3: verify file 2
    $c3 = $global:SignToolCalls[3]
    $expectedVerifyArgs2 = @('verify', '/pa', '/all', '/tw', 'C:\stage\app2.exe')
    if (($c3.ArgumentList -join ' ') -ne ($expectedVerifyArgs2 -join ' ')) {
        throw "Second file verify args mismatch: $(($c3.ArgumentList -join ' '))"
    }
    Write-Output '  PASS: Exact sign->verify order per file with SHA256/documented RFC3161 timestamp/dlib/metadata args verified'

    # Refusal on invalid signature status
    $global:SignToolCalls.Clear()
    $global:MockAuthenticodeStatus = 'HashMismatch'
    Assert-Throws -TestName 'Refuse invalid Authenticode status' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths @('C:\stage\app1.exe') -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'A valid timestamped Authenticode signature is required.'

    # Refusal on missing timestamp
    $global:SignToolCalls.Clear()
    $global:MockAuthenticodeStatus = 'Valid'
    $global:MockHasTimestamp = $false
    Assert-Throws -TestName 'Refuse missing timestamp' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths @('C:\stage\app1.exe') -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'A valid timestamped Authenticode signature is required.'
    $global:MockHasTimestamp = $true

    # Refusal on wrong publisher
    $global:SignToolCalls.Clear()
    $global:MockSignerName = 'UNTRUSTED THIRD PARTY'
    Assert-Throws -TestName 'Refuse untrusted publisher' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths @('C:\stage\app1.exe') -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'The Authenticode publisher is not Syntaur Enterprises LLC.'
    $global:MockSignerName = 'SYNTAUR ENTERPRISES LLC'

    # Stop on first sign failure: no retry, remaining file never touched
    $global:SignToolCalls.Clear()
    $global:MockSignToolFailOnCount = 1
    Assert-Throws -TestName 'Stop immediately on sign failure' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths @('C:\stage\app1.exe', 'C:\stage\app2.exe') -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'SignTool failed with exit code 1. No automatic retry was attempted.'
    if ($global:SignToolCalls.Count -ne 1) {
        throw "Expected exactly 1 call before stopping, got $($global:SignToolCalls.Count)"
    }
    Write-Output '  PASS: Failure stops on first error without retry or processing subsequent files'

    # Stop on verification failure: no retry, remaining file never touched
    $global:SignToolCalls.Clear()
    $global:MockSignToolFailOnCount = 2  # sign succeeds (1), verify fails (2)
    Assert-Throws -TestName 'Stop immediately on verify failure' `
        -ScriptBlock { Invoke-SyntaurArtifactSigning -LiteralPaths @('C:\stage\app1.exe', 'C:\stage\app2.exe') -SignToolPath 'C:\tools\signtool.exe' -DlibPath 'C:\tools\dlib.dll' -MetadataPath $validMetaPath } `
        -ExpectedMessageSubstring 'SignTool failed with exit code 1. No automatic retry was attempted.'
    if ($global:SignToolCalls.Count -ne 2) {
        throw "Expected exactly 2 calls before stopping, got $($global:SignToolCalls.Count)"
    }
    Write-Output '  PASS: Verification failure aborts without touching remaining files'

    # -------------------------------------------------------------
    # 4. scripts/build-windows-server-msi.ps1 preflight option tests
    # -------------------------------------------------------------
    Write-Output 'Running builder script option preflight tests...'

    # Preflight parameters use nonexistent dummy paths because parameter validation must trigger first
    $nonexistentParams = @{
        Version = '1.0.0'
        InputDirectory = 'C:\dummy\input'
        InputHashes = 'C:\dummy\hashes.json'
        OutputDirectory = (Join-Path $tempDir 'must-not-exist')
        WixPath = 'C:\dummy\wix.exe'
    }

    # Refuse when neither -DevelopmentUnsigned nor -SignedCandidate is specified
    Assert-Throws -TestName 'Builder requires DevelopmentUnsigned or SignedCandidate' `
        -ScriptBlock { & $builderScript @nonexistentParams } `
        -ExpectedMessageSubstring 'This development builder cannot produce a public package.'

    # Refuse mixed mode: both -DevelopmentUnsigned and -SignedCandidate
    Assert-Throws -TestName 'Builder rejects mixed mode (both flags)' `
        -ScriptBlock { & $builderScript @nonexistentParams -DevelopmentUnsigned -SignedCandidate } `
        -ExpectedMessageSubstring 'Unsigned development and signed-candidate options cannot be combined.'

    # Refuse mixed mode: -DevelopmentUnsigned with signing options
    Assert-Throws -TestName 'Builder rejects -DevelopmentUnsigned with -SigningMetadata' `
        -ScriptBlock { & $builderScript @nonexistentParams -DevelopmentUnsigned -SigningMetadata 'C:\dummy\meta.json' } `
        -ExpectedMessageSubstring 'Unsigned development and signed-candidate options cannot be combined.'

    Assert-Throws -TestName 'Builder rejects -DevelopmentUnsigned with -AcceptWix7Eula' `
        -ScriptBlock { & $builderScript @nonexistentParams -DevelopmentUnsigned -AcceptWix7Eula } `
        -ExpectedMessageSubstring 'Unsigned development and signed-candidate options cannot be combined.'

    # Refuse -SignedCandidate when missing required options (e.g. missing EULA acceptance)
    Assert-Throws -TestName 'Builder rejects -SignedCandidate without AcceptWix7Eula' `
        -ScriptBlock { & $builderScript @nonexistentParams -SignedCandidate -SigningMetadata 'C:\dummy\meta.json' -SignToolPath 'C:\dummy\signtool.exe' -DlibPath 'C:\dummy\dlib.dll' } `
        -ExpectedMessageSubstring 'A signed candidate requires signing metadata, SignTool, the Microsoft dlib, and explicit WiX 7 EULA acceptance.'

    # Refuse -SignedCandidate when missing metadata path
    Assert-Throws -TestName 'Builder rejects -SignedCandidate without SigningMetadata' `
        -ScriptBlock { & $builderScript @nonexistentParams -SignedCandidate -SignToolPath 'C:\dummy\signtool.exe' -DlibPath 'C:\dummy\dlib.dll' -AcceptWix7Eula } `
        -ExpectedMessageSubstring 'A signed candidate requires signing metadata, SignTool, the Microsoft dlib, and explicit WiX 7 EULA acceptance.'

    if (Test-Path -LiteralPath $nonexistentParams.OutputDirectory) {
        throw 'Rejected builder options created an output directory.'
    }
    Write-Output '  PASS: All builder option combinations and mixed-mode rejections validated before filesystem/tool access'

    Write-Output '=== ALL UNIT TESTS PASSED SUCCESSFULLY ==='
} finally {
    # Restore mocks and cleanup temp directory
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $origAuthenticodeCmd -and $origAuthenticodeCmd.CommandType -eq 'Function') {
        Set-Item -Path function:\Get-AuthenticodeSignature -Value $origAuthenticodeCmd.ScriptBlock
    } else {
        Remove-Item -Path function:\Get-AuthenticodeSignature -ErrorAction SilentlyContinue
    }
    if ($null -ne $origSignToolCmd) {
        Set-Item -Path function:\Invoke-SyntaurSigningTool -Value $origSignToolCmd.ScriptBlock
    } else {
        Remove-Item -Path function:\Invoke-SyntaurSigningTool -ErrorAction SilentlyContinue
    }
}
