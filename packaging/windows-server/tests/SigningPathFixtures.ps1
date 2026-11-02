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
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-LocalPath'
}, $true)
if ($null -eq $targetAst) { throw 'Could not locate actual Assert-LocalPath function.' }
. ([scriptblock]::Create($targetAst.Extent.Text))

$fixtureBase = Join-Path ([IO.Path]::GetTempPath()) ('SyntaurSigningPath-' + [guid]::NewGuid().ToString('N'))
$junctionTarget = Join-Path ([IO.Path]::GetTempPath()) ('SyntaurSigningPathTarget-' + [guid]::NewGuid().ToString('N'))
$junction = Join-Path $fixtureBase 'junction'
try {
    New-Item -ItemType Directory -Path $fixtureBase, $junctionTarget | Out-Null
    $subDir = Join-Path $fixtureBase 'nested'
    New-Item -ItemType Directory -Path $subDir | Out-Null
    $file = Join-Path $subDir 'payload.txt'
    Set-Content -LiteralPath $file -Value 'owned fixture only' -Encoding UTF8
    Assert-LocalPath -LiteralPath $file
    Write-Output 'PASS: Real nested file under StrictMode2'
    Assert-LocalPath -LiteralPath $subDir
    Write-Output 'PASS: Real directory under StrictMode2'
    Assert-LocalPath -LiteralPath (Join-Path $subDir 'missing.txt') -AllowMissingLeaf
    Write-Output 'PASS: Missing leaf validates its real parent under StrictMode2'

    $linkOutput = & cmd.exe /d /c "mklink /J `"$junction`" `"$junctionTarget`"" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Owned junction creation failed: $linkOutput" }
    $child = Join-Path $junction 'child.txt'
    Set-Content -LiteralPath $child -Value 'owned target only' -Encoding UTF8
    $refused = $false
    try { Assert-LocalPath -LiteralPath $child } catch {
        if ($_.Exception.Message -notlike '*Reparse paths are refused*') { throw }
        $refused = $true
    }
    if (!$refused) { throw 'Reparse ancestor was accepted.' }
    Write-Output 'PASS: Junction ancestor refused'
} finally {
    if (Test-Path -LiteralPath $junction) {
        if (([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw 'Owned junction identity changed; cleanup refused.'
        }
        [IO.Directory]::Delete($junction)
    }
    foreach ($owned in @($fixtureBase, $junctionTarget)) {
        if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Recurse -Force }
        if (Test-Path -LiteralPath $owned) { throw 'Owned fixture cleanup incomplete.' }
    }
}
Write-Output 'Owned strict-path fixtures removed.'
