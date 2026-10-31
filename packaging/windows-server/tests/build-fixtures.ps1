[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'OutputDirectory must not already exist.'
}
$fixtureSource = Join-Path $root 'LauncherFixtures.cs'
$launcherSource = Join-Path $root 'ServerLauncher.cs'
if (-not (Test-Path -LiteralPath $fixtureSource -PathType Leaf) -or
    -not (Test-Path -LiteralPath $launcherSource -PathType Leaf)) {
    throw 'SourceRoot must contain LauncherFixtures.cs and ServerLauncher.cs.'
}
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw 'Framework64 C# compiler not found.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($identity.User)
$inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
$propagation = [Security.AccessControl.PropagationFlags]::None
$allow = [Security.AccessControl.AccessControlType]::Allow
foreach ($sid in @($identity.User,
    (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),
    (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $sid, [Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance, $propagation, $allow)
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $output -AclObject $acl
$fixture = Join-Path $output 'LauncherFixtures.exe'
$launcher = Join-Path $output 'ServerLauncher.exe'
& $csc /nologo /warnaserror /target:exe /out:$fixture /reference:System.dll /reference:System.Windows.Forms.dll $fixtureSource
if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed.' }
& $csc /nologo /warnaserror /target:winexe /out:$launcher /reference:System.dll /reference:System.Windows.Forms.dll $launcherSource
if ($LASTEXITCODE -ne 0) { throw 'ServerLauncher compilation failed.' }
foreach ($name in @('syntaur.exe', 'syntaur-viewer.exe', 'foreign-fixture.exe')) {
    Copy-Item -LiteralPath $fixture -Destination (Join-Path $output $name)
}
Set-Content -LiteralPath (Join-Path $output 'fixture-mode.txt') -Value 'healthy' -NoNewline -Encoding Ascii
foreach ($source in @($fixtureSource, $launcherSource)) {
    $hash = Get-FileHash -LiteralPath $source -Algorithm SHA256
    Write-Output ('SOURCEHASH ' + $source + ' ' + $hash.Hash)
}
foreach ($name in @('LauncherFixtures.exe', 'ServerLauncher.exe', 'syntaur.exe', 'syntaur-viewer.exe', 'foreign-fixture.exe')) {
    $path = Join-Path $output $name
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    Write-Output ('EXEHASH ' + $name + ' ' + $hash.Hash)
}
Write-Output 'COMPILESUCCESS'
