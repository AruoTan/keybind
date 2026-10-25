param(
    [switch]$Test,
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
& $csc /nologo /target:library /optimize+ "/reference:$KeePassPath" /reference:System.Windows.Forms.dll "/out:$pluginPath" (Join-Path $sourceDir 'KeybindImeBridge.cs')
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
    & $csc /nologo /target:exe "/reference:$KeePassPath" /reference:System.Windows.Forms.dll "/out:$integrationExe" (Join-Path $sourceDir 'KeybindImeBridge.cs') (Join-Path $testDir 'BridgeTests.cs')
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
