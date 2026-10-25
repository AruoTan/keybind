# Install the pinned build reference for the optional Windows CI plugin job.
param()
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'KeePass build reference setup requires Windows.' }
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$lock = Get-Content -LiteralPath (Join-Path $projectRoot '.devcontainer\toolchain.json') -Raw | ConvertFrom-Json
$item = $lock.keepass
$cache = Join-Path $projectRoot 'build\cache'
$archive = Join-Path $cache "KeePass-$($item.version).zip"
$destination = Join-Path $cache "keepass-$($item.version)"
# A redirect service can return an HTML page with HTTP 200 on hosted runners.
# Every direct mirror is checked against the same official, pinned ZIP hash.
. (Join-Path $PSScriptRoot 'download-verified.ps1')
$urls = @($item.url) + @($item.fallbackUrls)
Get-KeybindVerifiedDownload -Urls $urls -Sha256 $item.sha256 -Destination $archive | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force
Write-Output (Join-Path $destination 'KeePass.exe')
