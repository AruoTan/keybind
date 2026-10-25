param(
    [string]$PluginPath = (Join-Path $PSScriptRoot '..\..\dist\plugins\keepass-ime\KeybindImeBridge.dll'),
    [string]$KeePassPath
)
$ErrorActionPreference = 'Stop'
if (!$KeePassPath -or !(Test-Path -LiteralPath $KeePassPath -PathType Leaf)) {
    throw 'Pass -KeePassPath pointing to KeePass.exe.'
}
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $KeePassPath).Path)
$expectedProduct = $assembly.GetType('KeePass.App.AppDefs').GetField('PluginProductName').GetValue($null)
$info = [Diagnostics.FileVersionInfo]::GetVersionInfo($PluginPath)
if ($info.ProductName -ne $expectedProduct) { throw 'KeePass plugin product marker missing.' }
$manager = [Activator]::CreateInstance($assembly.GetType('KeePass.Plugins.PluginManager'), $true)
$pluginHost = [Activator]::CreateInstance($assembly.GetType('KeePass.Plugins.DefaultPluginHost'), $true)
$manager.Initialize($pluginHost)
try {
    $manager.LoadPlugin($PluginPath, $null, $null, $true)
    $plugins = @($manager | ForEach-Object { $_ })
    if ($plugins.Count -ne 1) { throw "Expected one loaded plugin, found $($plugins.Count)." }
    if ($plugins[0].Interface.GetType().FullName -ne 'KeybindImeBridge.KeybindImeBridgeExt') {
        throw 'Unexpected plugin entry point.'
    }
    Write-Host 'PASS: KeePass product marker, discovery, compatibility check and Initialize.'
}
finally { $manager.UnloadAllPlugins() }
