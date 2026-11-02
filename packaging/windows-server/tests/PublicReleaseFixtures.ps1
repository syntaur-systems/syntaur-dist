#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$builderPath = Join-Path $repoRoot 'scripts\build-windows-server-msi.ps1'
if (!(Test-Path -LiteralPath $builderPath)) { throw "Builder script not found at $builderPath" }
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($builderPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Builder has PowerShell syntax errors.' }
$targetAst = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-SyntaurPublicReleaseContext'
}, $true)
if ($null -eq $targetAst) { throw 'Could not locate actual Assert-SyntaurPublicReleaseContext function.' }
. ([scriptblock]::Create($targetAst.Extent.Text))

$git = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$names = @('GITHUB_ACTIONS', 'GITHUB_REPOSITORY', 'GITHUB_REF', 'GITHUB_RUN_ATTEMPT', 'GITHUB_RUN_ID',
    'REL_VERSION', 'SRC_REF', 'SRC_COMMIT', 'ENGINE_COMMIT', 'DIST_COMMIT', 'GITHUB_SHA', 'RELEASE_CORRELATION')
$original = @{}
foreach ($n in $names) { $original[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
$version = '1.2.3'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('SyntaurPublicRelease-' + [guid]::NewGuid().ToString('N'))

function Get-Sha { param([string]$Version, [string]$Src, [string]$Engine, [string]$Dist)
    $text = (@('syntaur-release-operation-v2', $Version, ('v' + $Version), $Src, $Engine, $Dist) -join "`0") + "`0"
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') }) -join '' } finally { $sha.Dispose() }
}
function Invoke-Case {
    param([string]$Name, [hashtable]$Change, [string]$Expected, [string]$Root = $fixture)
    $env_ = [ordered]@{
        GITHUB_ACTIONS = 'true'; GITHUB_REPOSITORY = 'syntaur-systems/syntaur-dist'; GITHUB_REF = 'refs/heads/main'
        GITHUB_RUN_ATTEMPT = '1'; GITHUB_RUN_ID = '123456789'; REL_VERSION = $version; SRC_REF = 'v' + $version
        SRC_COMMIT = ('a' * 40); ENGINE_COMMIT = ('b' * 40); DIST_COMMIT = $script:head; GITHUB_SHA = $script:head
        RELEASE_CORRELATION = (Get-Sha $version ('a' * 40) ('b' * 40) $script:head)
    }
    foreach ($k in $Change.Keys) { $env_[$k] = $Change[$k] }
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $env_[$n], 'Process') }
    $message = $null
    try { Assert-SyntaurPublicReleaseContext -Root $Root -Version $version } catch { $message = $_.Exception.Message }
    if ($Expected -eq '') {
        if ($null -ne $message) { throw "$Name failed unexpectedly: $message" }
    } elseif ($null -eq $message -or $message -ne $Expected) { throw "$Name expected '$Expected' but got '$message'" }
    Write-Output "PASS: $Name"
}

$ci = 'Public release requires protected main CI.'
$attemptMsg = 'Public release requires its original workflow attempt.'
$identity = 'Invalid public release identity.'
$tuple = 'Public release source tuple does not match its checkout.'
$clean = 'Public release checkout must be clean.'
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    & $git -C $fixture init -q
    if ($LASTEXITCODE -ne 0) { throw 'Owned git init failed.' }
    Set-Content -LiteralPath (Join-Path $fixture 'tracked.txt') -Value 'owned' -Encoding UTF8
    & $git -C $fixture add tracked.txt
    & $git -c user.name=Fixture -c user.email=fixture@example.invalid -C $fixture commit -q -m fixture
    if ($LASTEXITCODE -ne 0) { throw 'Owned git commit failed.' }
    $script:head = (& $git -C $fixture rev-parse HEAD).Trim()

    Invoke-Case 'valid context' @{} ''
    Invoke-Case 'missing CI' @{ GITHUB_ACTIONS = $null } $ci
    Invoke-Case 'wrong repository' @{ GITHUB_REPOSITORY = 'other/repo' } $ci
    Invoke-Case 'wrong branch' @{ GITHUB_REF = 'refs/heads/dev' } $ci
    Invoke-Case 'attempt 2' @{ GITHUB_RUN_ATTEMPT = '2' } $attemptMsg
    Invoke-Case 'malformed source commit' @{ SRC_COMMIT = ('A' * 40) } $identity
    Invoke-Case 'version mismatch' @{ REL_VERSION = '1.2.4' } $identity
    Invoke-Case 'wrong GITHUB_SHA' @{ GITHUB_SHA = ('c' * 40) } $tuple
    Invoke-Case 'head mismatch' @{ DIST_COMMIT = ('c' * 40); GITHUB_SHA = ('c' * 40) } $tuple
    $expectedHash = Get-Sha $version ('a' * 40) ('b' * 40) $script:head
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') { throw 'Correlation fixture hash invalid.' }
    Invoke-Case 'correlation mismatch' @{ SRC_COMMIT = ('d' * 40) } 'Public release correlation mismatch.'
    Add-Content -LiteralPath (Join-Path $fixture 'tracked.txt') -Value 'dirty'
    Invoke-Case 'dirty tracked' @{} $clean
    & $git -C $fixture checkout -- tracked.txt
    Set-Content -LiteralPath (Join-Path $fixture 'untracked.txt') -Value 'dirty' -Encoding UTF8
    Invoke-Case 'dirty untracked' @{} $clean
} finally {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $original[$n], 'Process') }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    if (Test-Path -LiteralPath $fixture) { throw 'Owned fixture cleanup incomplete.' }
}
Write-Output 'Owned public-release fixtures removed.'
