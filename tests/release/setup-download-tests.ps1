# Network-independent regression checks; also run under Windows PowerShell 5.1 in CI.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot '.devcontainer/scripts/download-verified.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('keybind-download-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$trustedBytes = [Text.Encoding]::UTF8.GetBytes('trusted pinned download fixture')
$sha256 = [Security.Cryptography.SHA256]::Create()
try { $expected = [BitConverter]::ToString($sha256.ComputeHash($trustedBytes)).Replace('-', '').ToLowerInvariant() }
finally { $sha256.Dispose() }
$script:requests = New-Object 'System.Collections.Generic.List[string]'
$script:responses = @{}

# Shadow the network cmdlet only inside this test process.
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, [switch]$PassThru, $UserAgent, $TimeoutSec, $MaximumRedirection)
    if ($PassThru) { throw 'PassThru must not be used with OutFile.' }
    $script:requests.Add($Uri)
    if ($UserAgent -ne 'keybind-build' -or !$TimeoutSec) { throw 'Missing download request settings.' }
    $response = $script:responses[$Uri]
    if (!$response) { throw "Unexpected request: $Uri" }
    [IO.File]::WriteAllBytes($OutFile, [byte[]]$response.Body)
    if ($response.Error) { throw $response.Error }
}

function Assert-Equal($Actual, $Expected, $Label) {
    if ($Actual -ne $Expected) { throw "${Label}: expected '$Expected', got '$Actual'." }
}
function Assert-NoPartialFiles {
    if (@(Get-ChildItem -LiteralPath $temporary -Filter '*.partial').Count) { throw 'Partial files were retained.' }
}

try {
    $primary = 'https://fixture.invalid/primary.zip'
    $mirror = 'https://fixture.invalid/mirror.zip'
    $destination = Join-Path $temporary 'verified.zip'
    [IO.File]::WriteAllBytes($destination, $trustedBytes)
    $result = Get-KeybindVerifiedDownload -Urls @($primary) -Sha256 $expected -Destination $destination
    Assert-Equal $result $destination 'Cache result'
    Assert-Equal $script:requests.Count 0 'Valid cache must avoid network'
    Write-Output 'PASS: matching cache is reused without a request'

    Remove-Item -LiteralPath $destination
    $script:responses[$primary] = @{ Body = [Text.Encoding]::UTF8.GetBytes('<html>download page</html>'); ContentType = 'text/html' }
    $script:responses[$mirror] = @{ Body = $trustedBytes; ContentType = 'application/zip' }
    $downloadWarnings = @()
    $result = Get-KeybindVerifiedDownload -Urls @($primary, $mirror) -Sha256 $expected -Destination $destination `
        -WarningAction SilentlyContinue -WarningVariable downloadWarnings
    Assert-Equal $script:requests.Count 2 'HTML response must fall back'
    Assert-Equal (Get-FileHash -LiteralPath $result -Algorithm SHA256).Hash.ToLowerInvariant() $expected 'Fallback hash'
    if (($downloadWarnings -join ' ') -notmatch 'format=HTML' -or ($downloadWarnings -join ' ') -notmatch 'actual=') {
        throw 'Hash failures must identify the response and actual hash.'
    }
    Assert-NoPartialFiles
    Write-Output 'PASS: HTML response is rejected and a matching mirror is accepted'

    $script:requests.Clear()
    [IO.File]::WriteAllBytes($destination, [Text.Encoding]::UTF8.GetBytes('corrupted cache'))
    $script:responses[$primary] = @{ Body = [byte[]]@(1, 2); Error = 'Connection interrupted' }
    $result = Get-KeybindVerifiedDownload -Urls @($primary, $mirror) -Sha256 $expected -Destination $destination -WarningAction SilentlyContinue
    Assert-Equal $script:requests.Count 2 'Corrupt cache and network failure must retry a mirror'
    Assert-Equal (Get-FileHash -LiteralPath $result -Algorithm SHA256).Hash.ToLowerInvariant() $expected 'Recovered download hash'
    Assert-NoPartialFiles
    Write-Output 'PASS: corrupt cache and interrupted requests recover through a verified mirror'

    Remove-Item -LiteralPath $destination
    $script:responses[$primary] = @{ Body = [byte[]]@() }
    $emptyWarnings = @()
    $result = Get-KeybindVerifiedDownload -Urls @($primary, $mirror) -Sha256 $expected -Destination $destination `
        -WarningAction SilentlyContinue -WarningVariable emptyWarnings
    if (($emptyWarnings -join ' ') -notmatch 'bytes=0; format=empty') { throw 'Empty response diagnostics missing.' }
    Assert-Equal $result $destination 'Empty response fallback result'
    Assert-NoPartialFiles
    Write-Output 'PASS: empty responses are rejected and recovered through a verified mirror'

    Remove-Item -LiteralPath $destination
    $script:responses[$primary] = @{ Body = [byte[]]@(1, 2, 3); ContentType = 'application/zip' }
    $rejected = $false
    try {
        Get-KeybindVerifiedDownload -Urls @($primary) -Sha256 $expected -Destination $destination -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $rejected = $_.Exception.Message -like 'No download matched the pinned SHA256.*'
    }
    if (!$rejected -or (Test-Path -LiteralPath $destination)) { throw 'Unverified files must never become the download cache.' }
    Assert-NoPartialFiles
    Write-Output 'PASS: all failures reject the download and clean partial files'
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
