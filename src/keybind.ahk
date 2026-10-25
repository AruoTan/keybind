#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True
#NoTrayIcon

#Include %A_LineFile%/../modules/keepass-ime/keepass-ime.ahk
#Include %A_LineFile%/../modules/mouse.ahk
#Include %A_LineFile%/../modules/keyboard.ahk
#Include %A_LineFile%/../modules/virtual-desktop/virtual-desktop.ahk
#Include %A_LineFile%/../modules/remote-desktop/remote-desktop.ahk

KeePassImeInit()
MouseInit()
if VirtualDesktopInit()
    RemoteDesktopInit()
