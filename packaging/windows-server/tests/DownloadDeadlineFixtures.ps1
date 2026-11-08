# Standalone WindowsPowerShell 5.1 fixture harness for Install-PinnedReleaseAsset deadline verification
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Installer script not found at literal path: $InstallerPath"
}

# 1. Parse AST to extract the ACTUAL Install-PinnedReleaseAsset function definition
$Tokens = $null
$Errors = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $InstallerPath).Path,
    [ref]$Tokens,
    [ref]$Errors
)

if ($Errors -and $Errors.Count -gt 0) {
    throw "Syntax errors parsing installer script: $($Errors[0].Message)"
}

$FunctionPredicate = {
    param($Node)
    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $Node.Name -ceq "Install-PinnedReleaseAsset"
}

$FunctionAst = $Ast.Find($FunctionPredicate, $true)
if ($null -eq $FunctionAst) {
    throw "Function Install-PinnedReleaseAsset not found in $InstallerPath"
}

$ScriptBlock = [scriptblock]::Create($FunctionAst.Extent.Text)
. $ScriptBlock

# Create disposable private fixture root
$FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dw-deadline-fix-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $FixtureRoot | Out-Null

$script:IwrCallCount = 0
$script:IwrLastTimeoutSec = $null
$script:IwrMode = "none" # "timeout" or "success"
$script:IwrPayloadBytes = $null

function script:Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [switch]$UseBasicParsing,
        [int]$TimeoutSec
    )

    $script:IwrCallCount++
    if ($PSBoundParameters.ContainsKey("TimeoutSec")) {
        $script:IwrLastTimeoutSec = $TimeoutSec
    } else {
        $script:IwrLastTimeoutSec = $null
    }

    if ($script:IwrMode -eq "timeout") {
        # Simulate partial bytes written before connection timeout
        [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@(0xDE, 0xAD, 0xBE, 0xEF))
        $WebException = New-Object System.Net.WebException(
            "The operation has timed out.",
            [System.Net.WebExceptionStatus]::Timeout
        )
        throw $WebException
    } elseif ($script:IwrMode -eq "success") {
        if ($null -ne $script:IwrPayloadBytes) {
            [System.IO.File]::WriteAllBytes($OutFile, $script:IwrPayloadBytes)
        } else {
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@(0x01, 0x02, 0x03, 0x04))
        }
    } else {
        throw "Unexpected mock mode: $script:IwrMode"
    }
}

$script:AllowedSafePaths = @{}
function script:Test-SafeInstallEntry {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][bool]$Container
    )
    return $script:AllowedSafePaths.ContainsKey($LiteralPath)
}

try {
    # -------------------------------------------------------------------------
    # Case 1: Timeout case
    # -------------------------------------------------------------------------
    $DestFile1 = Join-Path $FixtureRoot "target-timeout.bin"
    $PriorBytes = [System.Text.Encoding]::UTF8.GetBytes("PRESERVED_TARGET_CONTENT")
    [System.IO.File]::WriteAllBytes($DestFile1, $PriorBytes)
    $script:AllowedSafePaths[$DestFile1] = $true

    $script:IwrCallCount = 0
    $script:IwrLastTimeoutSec = $null
    $script:IwrMode = "timeout"

    $TimedOut = $false
    try {
        Install-PinnedReleaseAsset -Url "https://example.invalid/asset.bin" `
            -LiteralPath $DestFile1 `
            -ExpectedSha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" `
            -Label "timeout asset"
    } catch [System.Net.WebException] {
        $TimedOut = $_.Exception.Status -eq [System.Net.WebExceptionStatus]::Timeout
    }

    if (-not $TimedOut) {
        throw "TimeoutCase failed: Install-PinnedReleaseAsset did not throw on timeout"
    }
    if ($script:IwrCallCount -ne 1) {
        throw "TimeoutCase failed: expected exactly 1 Invoke-WebRequest call, got $($script:IwrCallCount)"
    }
    if ($script:IwrLastTimeoutSec -ne 60) {
        throw "TimeoutCase failed: expected literal TimeoutSec=60, got $($script:IwrLastTimeoutSec)"
    }
    $ActualBytes1 = [System.IO.File]::ReadAllBytes($DestFile1)
    if ([System.Convert]::ToBase64String($ActualBytes1) -ne [System.Convert]::ToBase64String($PriorBytes)) {
        throw "TimeoutCase failed: prior destination bytes were modified"
    }
    $LeftoverPartFiles = Get-ChildItem -LiteralPath $FixtureRoot -Filter "*.part.*" -Force
    if ($LeftoverPartFiles.Count -gt 0) {
        throw "TimeoutCase failed: part file was not removed on timeout"
    }
    Write-Host "PASS: TimeoutCase verified"

    # -------------------------------------------------------------------------
    # Case 2: Success case
    # -------------------------------------------------------------------------
    $DestFile2 = Join-Path $FixtureRoot "target-success.bin"
    $KnownBytes = [System.Text.Encoding]::UTF8.GetBytes("VERIFIED_PAYLOAD_DATA_CONTENT")
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $KnownHash = -join ($Sha256.ComputeHash($KnownBytes) | ForEach-Object { "{0:x2}" -f $_ })
    $Sha256.Dispose()

    $script:AllowedSafePaths[$DestFile2] = $true
    $script:IwrCallCount = 0
    $script:IwrLastTimeoutSec = $null
    $script:IwrMode = "success"
    $script:IwrPayloadBytes = $KnownBytes

    Install-PinnedReleaseAsset -Url "https://example.invalid/asset-ok.bin" `
        -LiteralPath $DestFile2 `
        -ExpectedSha256 $KnownHash `
        -Label "success asset"

    if ($script:IwrCallCount -ne 1) {
        throw "SuccessCase failed: expected exactly 1 Invoke-WebRequest call, got $($script:IwrCallCount)"
    }
    if ($script:IwrLastTimeoutSec -ne 60) {
        throw "SuccessCase failed: expected literal TimeoutSec=60, got $($script:IwrLastTimeoutSec)"
    }
    if (-not (Test-Path -LiteralPath $DestFile2)) {
        throw "SuccessCase failed: destination file does not exist"
    }
    $ActualBytes2 = [System.IO.File]::ReadAllBytes($DestFile2)
    if ([System.Convert]::ToBase64String($ActualBytes2) -ne [System.Convert]::ToBase64String($KnownBytes)) {
        throw "SuccessCase failed: destination bytes do not match expected payload"
    }
    $LeftoverPartFiles2 = Get-ChildItem -LiteralPath $FixtureRoot -Filter "*.part.*" -Force
    if ($LeftoverPartFiles2.Count -gt 0) {
        throw "SuccessCase failed: leftover part files detected after success"
    }
    Write-Host "PASS: SuccessCase verified"

    # -------------------------------------------------------------------------
    # Case 3: Wrong hash refused without replacing destination
    # -------------------------------------------------------------------------
    $DestFile3 = Join-Path $FixtureRoot "target-wronghash.bin"
    $OriginalDestBytes = [System.Text.Encoding]::UTF8.GetBytes("ORIGINAL_UNTOUCHED_DESTINATION")
    [System.IO.File]::WriteAllBytes($DestFile3, $OriginalDestBytes)
    $script:AllowedSafePaths[$DestFile3] = $true

    $script:IwrCallCount = 0
    $script:IwrLastTimeoutSec = $null
    $script:IwrMode = "success"
    $script:IwrPayloadBytes = [System.Text.Encoding]::UTF8.GetBytes("NEW_MISMATCHED_DATA")

    $MismatchedHash = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    $HashRejected = $false
    try {
        Install-PinnedReleaseAsset -Url "https://example.invalid/asset-wronghash.bin" `
            -LiteralPath $DestFile3 `
            -ExpectedSha256 $MismatchedHash `
            -Label "wronghash asset"
    } catch {
        $HashRejected = $_.Exception.Message -ceq "wronghash asset did not match the hash pinned into this signed installer"
    }

    if ($script:IwrCallCount -ne 1 -or $script:IwrLastTimeoutSec -ne 60) { throw "WrongHashCase dispatched incorrectly" }
    if (-not $HashRejected) {
        throw "WrongHashCase failed: installer did not throw on hash mismatch"
    }
    $ActualBytes3 = [System.IO.File]::ReadAllBytes($DestFile3)
    if ([System.Convert]::ToBase64String($ActualBytes3) -ne [System.Convert]::ToBase64String($OriginalDestBytes)) {
        throw "WrongHashCase failed: destination file was replaced despite wrong hash"
    }
    $LeftoverPartFiles3 = Get-ChildItem -LiteralPath $FixtureRoot -Filter "*.part.*" -Force
    if ($LeftoverPartFiles3.Count -gt 0) {
        throw "WrongHashCase failed: part file was not removed on hash mismatch"
    }
    Write-Host "PASS: WrongHashCase verified"

} finally {
    # Restore mocks / remove functions
    Remove-Item -Path "function:\Invoke-WebRequest" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "function:\Test-SafeInstallEntry" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "function:\Install-PinnedReleaseAsset" -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name "IwrCallCount" -Scope Script -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name "IwrLastTimeoutSec" -Scope Script -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name "IwrMode" -Scope Script -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name "IwrPayloadBytes" -Scope Script -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name "AllowedSafePaths" -Scope Script -Force -ErrorAction SilentlyContinue

    # Clean up disposable fixture directory
    if (Test-Path -LiteralPath $FixtureRoot) {
        Remove-Item -LiteralPath $FixtureRoot -Recurse -Force -ErrorAction Stop
    }
}

if (Test-Path -LiteralPath $FixtureRoot) { throw "Owned download fixture cleanup incomplete" }
Write-Output "PASS: owned download fixtures cleaned"
