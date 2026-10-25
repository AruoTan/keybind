#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/keepass-ime/keepass-ime.ahk
KeePassImeInit()
Persistent
SetTimer ExitApp, -60000
