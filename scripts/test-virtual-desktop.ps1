param(
    [string]$AhkPath,
    [string]$DllPath = (Join-Path $PSScriptRoot '..\dist\windows-x64\VirtualDesktopAccessor.dll'),
    [switch]$NativeCheck,
    [switch]$Exercise,
    [switch]$PlacementOnly,
    [string]$PlacementTestDirectory = (Join-Path $PSScriptRoot '..\build\tests\window-placement\native')
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'These tests require Windows and AutoHotkey v2 x64.' }
if (!$AhkPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\autohotkey\current\v2\AutoHotkey64.exe')
    )
    $AhkPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$AhkPath -or !(Test-Path -LiteralPath $AhkPath)) { throw 'Pass -AhkPath pointing to AutoHotkey v2 AutoHotkey64.exe.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
function Invoke-AhkTest([string]$Name, [string[]]$ExtraArguments = @(), [string]$Group = 'virtual-desktop') {
    $testDir = Join-Path $projectRoot "tests\$Group"
    $outputDir = Join-Path $projectRoot "build\tests\$Group"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $script = Join-Path $testDir "$Name.ahk"
    $log = Join-Path $outputDir "$Name.log"
    $stdout = Join-Path $outputDir "$Name.stdout.log"
    $stderr = Join-Path $outputDir "$Name.stderr.log"
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    # Windows paths cannot contain quotes; reject them in extra arguments too.
    $arguments = @('/ErrorStdOut=UTF-8', $script, $log) + $ExtraArguments
    $quoted = $arguments | ForEach-Object {
        if ($_ -match '"') { throw 'Unexpected quote in test argument.' }
        '"' + $_ + '"'
    }
    $process = Start-Process -FilePath $AhkPath -ArgumentList $quoted -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Native calls into undocumented shell interfaces cannot be forcibly timed
    # out inside AHK. The separate test process has an outer deadline as well.
    if (!$process.WaitForExit(60000)) {
        $process.Kill()
        throw "$Name exceeded 60 seconds. Inspect $outputDir and the Windows desktop state."
    }
    $process.WaitForExit()
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Out-Host }
    if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $log)) {
        Get-Content -LiteralPath $stdout, $stderr | Out-Host
        throw "$Name failed; see $outputDir"
    }
}

if ($PlacementOnly) {
    $nativeDirectory = (Resolve-Path -LiteralPath $PlacementTestDirectory).Path
    Invoke-AhkTest 'placement-tests' -Group 'window-placement'
    Invoke-AhkTest 'pre-show-tests' -Group 'window-placement' -ExtraArguments @($nativeDirectory)
    Invoke-AhkTest 'bridge-tests' -Group 'window-placement' -ExtraArguments @((Join-Path (Split-Path $nativeDirectory -Parent) 'production'))
    exit
}
Invoke-AhkTest 'controller-tests'
Invoke-AhkTest 'monitor-tests'
Invoke-AhkTest 'placement-tests' -Group 'window-placement'
Invoke-AhkTest 'rdp-tests'
Invoke-AhkTest 'indicator-tests'
Invoke-AhkTest 'window-tests'
if ($NativeCheck -or $Exercise) {
    $resolvedDll = (Resolve-Path -LiteralPath $DllPath).Path
    $nativeArguments = @($resolvedDll)
    if ($Exercise) { $nativeArguments += '--exercise' }
    Invoke-AhkTest 'native-check' $nativeArguments
}
