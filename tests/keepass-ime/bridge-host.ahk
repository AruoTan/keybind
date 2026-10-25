#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%/../../src/modules/keepass-ime.ahk
KeePassImeInit()
Persistent
SetTimer ExitApp, -60000
