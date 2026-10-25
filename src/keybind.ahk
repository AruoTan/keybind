#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True
#NoTrayIcon

#Include %A_ScriptDir%/modules/keepass-ime.ahk
#Include %A_ScriptDir%/modules/mouse.ahk
#Include %A_ScriptDir%/modules/keyboard.ahk
#Include %A_ScriptDir%/modules/virtual-desktop/virtual-desktop.ahk

KeePassImeInit()
MouseInit()
VirtualDesktopInit()
