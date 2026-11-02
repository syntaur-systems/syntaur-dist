# Pipeline scope: compatibility-channels — Microsoft SignTool integration for
# the existing server package. This file defines functions and performs no login.
Set-StrictMode -Version 2.0

function Read-SyntaurArtifactSigningMetadata {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $item = Get-Item -LiteralPath $LiteralPath -Force
    if ($item.PSIsContainer -or $item.Length -gt 4096) { throw 'Invalid signing metadata file.' }
    $value = [IO.File]::ReadAllText($item.FullName) | ConvertFrom-Json
    $names = @($value.PSObject.Properties.Name | Sort-Object)
    if (($names -join ',') -cne 'CertificateProfileName,CodeSigningAccountName,Endpoint') {
        throw 'Signing metadata must contain only the three public profile fields.'
    }
    if ($value.Endpoint -cne 'https://wus2.codesigning.azure.net/' -or
        $value.CodeSigningAccountName -cne 'syntaurenterprisesllc' -or
        $value.CertificateProfileName -cnotmatch '^[A-Za-z0-9-]{1,100}$') {
        throw 'Signing metadata does not select the Syntaur signing account.'
    }
    # A build must use the deliberately authenticated Azure CLI identity.
    # Do not fall through to unrelated environment secrets, IDEs or a browser.
    return [ordered]@{
        Endpoint = $value.Endpoint
        CodeSigningAccountName = $value.CodeSigningAccountName
        CertificateProfileName = $value.CertificateProfileName
        ExcludeCredentials = @(
            'EnvironmentCredential', 'WorkloadIdentityCredential',
            'ManagedIdentityCredential', 'SharedTokenCacheCredential',
            'VisualStudioCredential', 'VisualStudioCodeCredential',
            'AzurePowerShellCredential', 'AzureDeveloperCliCredential',
            'InteractiveBrowserCredential'
        )
    }
}

function Invoke-SyntaurSigningTool {
    param([string]$SignToolPath, [string[]]$ArgumentList)
    & $SignToolPath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "SignTool failed with exit code $LASTEXITCODE. No automatic retry was attempted." }
}

function Assert-SyntaurPublisherSignature {
    param([string]$LiteralPath, [string]$SignToolPath)
    $signature = Get-AuthenticodeSignature -LiteralPath $LiteralPath
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $null -eq $signature.TimeStamperCertificate) {
        throw 'A valid timestamped Authenticode signature is required.'
    }
    $publisher = $signature.SignerCertificate.GetNameInfo(
        [Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    if ($publisher -cne 'SYNTAUR ENTERPRISES LLC') { throw 'The Authenticode publisher is not Syntaur Enterprises LLC.' }
    Invoke-SyntaurSigningTool -SignToolPath $SignToolPath -ArgumentList @(
        'verify', '/pa', '/all', '/tw', $LiteralPath
    )
}

function Invoke-SyntaurArtifactSigning {
    param(
        [Parameter(Mandatory = $true)][string[]]$LiteralPaths,
        [Parameter(Mandatory = $true)][string]$SignToolPath,
        [Parameter(Mandatory = $true)][string]$DlibPath,
        [Parameter(Mandatory = $true)][string]$MetadataPath
    )
    # The builder admits exact staged inputs and tool paths before calling us.
    # Sign exactly the requested files; never glob adjacent outputs or retry an
    # uncertain submission. A failure leaves the candidate unpublished.
    if ($LiteralPaths.Count -lt 1 -or $LiteralPaths.Count -gt 8) { throw 'Unexpected signing input count.' }
    if (@($LiteralPaths | Select-Object -Unique).Count -ne $LiteralPaths.Count) { throw 'Duplicate signing input.' }
    foreach ($path in $LiteralPaths) {
        Invoke-SyntaurSigningTool -SignToolPath $SignToolPath -ArgumentList @(
            'sign', '/fd', 'SHA256', '/tr', 'http://timestamp.acs.microsoft.com/',
            '/td', 'SHA256', '/dlib', $DlibPath, '/dmdf', $MetadataPath, $path
        )
        Assert-SyntaurPublisherSignature -LiteralPath $path -SignToolPath $SignToolPath
    }
}
