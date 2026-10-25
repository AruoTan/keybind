param(
    [switch]$Test,
    [switch]$Package,
    [string]$KeePassPath,
    [string]$AhkPath
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'The optional KeePass C# plugin build requires Windows.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceDir = Join-Path $projectRoot 'plugins\keepass-ime'
$testDir = Join-Path $projectRoot 'tests\keepass-ime'
$buildDir = Join-Path $projectRoot 'build\keepass-ime'
$testBuildDir = Join-Path $projectRoot 'build\tests\keepass-ime'
$distDir = Join-Path $projectRoot 'dist\plugins\keepass-ime'
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$' -or @($version.Split('.') | Where-Object { [int64]$_ -gt 65535 }).Count) {
    throw 'VERSION must contain a stable Windows-compatible major.minor.patch version.'
}
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!$KeePassPath) {
    $installed = Get-Command KeePass.exe -ErrorAction SilentlyContinue
    if ($installed) { $KeePassPath = $installed.Source }
    else { $KeePassPath = Join-Path $env:USERPROFILE 'scoop\apps\keepass\current\KeePass.exe' }
}
if (!$KeePassPath -or !(Test-Path -LiteralPath $KeePassPath -PathType Leaf)) {
    throw 'Pass -KeePassPath pointing to KeePass.exe.'
}
$KeePassPath = (Resolve-Path -LiteralPath $KeePassPath).Path
if (!(Test-Path -LiteralPath $csc)) { throw 'The .NET Framework x64 C# compiler is missing.' }
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$pluginPath = Join-Path $buildDir 'KeybindImeBridge.dll'
$versionSource = Join-Path $buildDir 'AssemblyVersion.cs'
Set-Content -LiteralPath $versionSource -Encoding ASCII -Value ('[assembly: System.Reflection.AssemblyVersion("' + $version + '.0")]')
& $csc /nologo /target:library /optimize+ "/reference:$KeePassPath" /reference:System.Windows.Forms.dll "/out:$pluginPath" (Join-Path $sourceDir 'KeybindImeBridge.cs') $versionSource
if ($LASTEXITCODE -ne 0) { throw 'Plugin compilation failed.' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testDir 'plugin-load.ps1') -PluginPath $pluginPath -KeePassPath $KeePassPath
if ($LASTEXITCODE -ne 0) { throw 'KeePass plugin loading test failed.' }

if ($Test) {
    if (!$AhkPath) { $AhkPath = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe' }
    if (!(Test-Path -LiteralPath $AhkPath)) { throw 'Pass -AhkPath pointing to AutoHotkey v2 x64.' }
    New-Item -ItemType Directory -Path $testBuildDir -Force | Out-Null
    $imeLog = Join-Path $testBuildDir 'ime-test.log'
    & $AhkPath /ErrorStdOut (Join-Path $testDir 'ime-roundtrip.ahk') $imeLog | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'IME round-trip test failed.' }
    Get-Content -LiteralPath $imeLog
    $integrationExe = Join-Path $testBuildDir 'BridgeTests.exe'
    & $csc /nologo /target:exe "/reference:$KeePassPath" /reference:System.Windows.Forms.dll "/out:$integrationExe" (Join-Path $sourceDir 'KeybindImeBridge.cs') $versionSource (Join-Path $testDir 'BridgeTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Integration test compilation failed.' }
    Copy-Item -LiteralPath $KeePassPath -Destination (Join-Path $testBuildDir 'KeePass.exe') -Force
    $hostScript = Join-Path $testDir 'bridge-host.ahk'
    $hostProcess = Start-Process -FilePath $AhkPath -ArgumentList @('/ErrorStdOut', ('"' + $hostScript + '"')) -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 600
        & $integrationExe
        if ($LASTEXITCODE -ne 0) { throw 'Cross-process integration tests failed.' }
    }
    finally {
        if (!$hostProcess.HasExited) { Stop-Process -Id $hostProcess.Id }
    }
}
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Copy-Item -LiteralPath $pluginPath -Destination (Join-Path $distDir 'KeybindImeBridge.dll') -Force
Write-Host "Built: $(Join-Path $distDir 'KeybindImeBridge.dll')"

if ($Package) {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $distDir 'LICENSE.txt') -Force
    $dllPath = Join-Path $distDir 'KeybindImeBridge.dll'
    $metadata = [ordered]@{
        version = $version
        artifact = 'KeybindImeBridge.dll'
        sha256 = (Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash.ToLowerInvariant()
        keepassVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($KeePassPath).FileVersion
        pluginLoadTest = $true
        imeRoundtripTest = [bool]$Test
        crossProcessTest = [bool]$Test
    }
    $metadataDir = Join-Path $projectRoot 'build\metadata'
    New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $metadataDir 'keepass-build.json') -Encoding UTF8
    $oldManifest = Join-Path $distDir 'manifest.json'
    if (Test-Path -LiteralPath $oldManifest) { Remove-Item -LiteralPath $oldManifest -Force }
    @"
Keybind IME Bridge $version (optional KeePass plugin)

Exit KeePass, then extract this archive into your KeePass Plugins directory.
Restart KeePass and check the plugin list for Keybind IME Bridge.
Keybind must be running when KeePass performs auto-type.
To uninstall, exit KeePass and remove KeybindImeBridge.dll from Plugins.

Built against KeePass $($metadata.keepassVersion); plugin loading was checked.
Real IME interactions and elevated target windows require Windows testing.
This archive contains no KeePass executable or password database.
"@ | Set-Content -LiteralPath (Join-Path $distDir 'README.txt') -Encoding UTF8
    $archive = Join-Path $projectRoot 'dist\keybind-keepass-ime.zip'
    Compress-Archive -LiteralPath @($dllPath, (Join-Path $distDir 'README.txt'), (Join-Path $distDir 'LICENSE.txt')) -DestinationPath $archive -Force
    Write-Host "Packaged: $archive"
}
