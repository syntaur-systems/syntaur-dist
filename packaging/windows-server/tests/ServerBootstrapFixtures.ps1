#Requires -Version 5.1
# Pure fixture: no installer, elevation, download, signing, or network is run.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'install.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Bootstrap syntax errors.' }
$function = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-SyntaurServerPackage'}, $true)
if ($null -eq $function) { throw 'Actual server bootstrap function missing.' }
. ([scriptblock]::Create($function.Extent.Text))
$Version = '1.2.3'
$payload = [Text.Encoding]::UTF8.GetBytes('owned MSI fixture; never executed')
$sha = [Security.Cryptography.SHA256]::Create()
try { $expectedHash = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }

function Assert-PrivateInstallDirectory { param($LiteralPath) [void][IO.Directory]::CreateDirectory($LiteralPath) }
function Install-PinnedReleaseAsset {
    param($Url, $LiteralPath, $ExpectedSha256, $Label)
    if ($Url -cne 'https://github.com/syntaur-systems/syntaur-dist/releases/download/v1.2.3/syntaur-server-windows-x86_64.msi') { throw 'Wrong immutable package URL.' }
    $script:package = $LiteralPath
    [IO.File]::WriteAllBytes($LiteralPath, $payload)
}
function Get-AuthenticodeSignature {
    param($LiteralPath)
    $cert = New-Object PSObject
    $cert | Add-Member ScriptMethod GetNameInfo { param($kind, $issuer) return $script:publisher }
    [pscustomobject]@{Status=$script:signatureStatus; SignerCertificate=$cert; TimeStamperCertificate=$script:timestamp}
}
function Start-Process {
    param($FilePath, $Verb, [switch]$Wait, [switch]$PassThru, $ArgumentList)
    $script:launches++
    if ($FilePath -cne (Join-Path $env:windir 'System32\msiexec.exe') -or $Verb -or !$Wait -or !$PassThru -or
        ($ArgumentList -join '|') -cne ('/i|"' + $script:package + '"|ACCEPT_EULA=Yes|/norestart')) { throw 'Incorrect normal installer invocation.' }
    $openedForWrite = $false
    try { $h = [IO.File]::Open($script:package, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $h.Dispose(); $openedForWrite = $true } catch [IO.IOException] {}
    if ($openedForWrite) { throw 'Verified MSI was writable during elevation.' }
    if ($script:cancel) { throw 'Fixture UAC canceled.' }
    [pscustomobject]@{ExitCode=$script:exitCode}
}
function Invoke-Case {
    param([string]$Name, [string]$Expected, [int]$ExpectedLaunches)
    $script:launches=0; $script:package=$null
    $message=$null
    try { Install-SyntaurServerPackage } catch { $message=$_.Exception.Message }
    if ($Expected -eq '') { if ($null -ne $message) { throw "$Name failed: $message" } }
    elseif ($null -eq $message -or !$message.Contains($Expected)) { throw "$Name expected '$Expected', got '$message'" }
    if ($script:launches -ne $ExpectedLaunches) { throw "$Name dispatched an unexpected installer count." }
    if (!$script:package -or (Test-Path -LiteralPath (Split-Path $script:package -Parent))) { throw "$Name left owned fixture files." }
    Write-Output "PASS: $Name"
}
$ServerMsiSha256=$expectedHash; $script:signatureStatus='Valid'; $script:timestamp=New-Object PSObject
$script:publisher='SYNTAUR ENTERPRISES LLC'; $script:cancel=$false; $script:exitCode=0
Invoke-Case 'normal MSI handoff and held bytes' '' 1
$script:exitCode=3010
Invoke-Case 'restart required is successful' '' 1
$script:exitCode=1603
Invoke-Case 'installer failure has no fallback' 'code 1603' 1
$script:exitCode=0; $script:cancel=$true
Invoke-Case 'canceled elevation has no retry' 'Fixture UAC canceled' 1
$script:cancel=$false; $script:publisher='Other publisher'
Invoke-Case 'wrong publisher blocks elevation' 'not timestamped and trusted' 0
$script:publisher='SYNTAUR ENTERPRISES LLC'; $script:timestamp=$null
Invoke-Case 'missing timestamp blocks elevation' 'not timestamped and trusted' 0
$script:timestamp=New-Object PSObject; $script:signatureStatus='HashMismatch'
Invoke-Case 'untrusted signature blocks elevation' 'not timestamped and trusted' 0
$script:signatureStatus='Valid'; $ServerMsiSha256='0'*64
Invoke-Case 'changed MSI bytes block elevation' 'changed before verification' 0
