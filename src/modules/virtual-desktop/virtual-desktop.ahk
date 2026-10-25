; Dynamic virtual desktop entry points and keyboard registration.
#Include %A_LineFile%/../controller.ahk
#Include %A_LineFile%/../native.ahk
#Include %A_LineFile%/../windows.ahk

; AutoHotkey v2, Windows x64. Including this file alone registers no hotkeys.
VirtualDesktopInit() {
    global VirtualDesktopState
    try {
        dll := A_IsCompiled ? A_ScriptDir "\VirtualDesktopAccessor.dll"
            : A_ScriptDir "\..\dist\windows-x64\VirtualDesktopAccessor.dll"
        api := VDNative(dll)
        api.Snapshot() ; Includes GUID ABI and index round-trip checks.
        api.Current()
        VirtualDesktopState := {
            Controller: VDController(api, VDWindows()), Held: Map("Left", false, "Right", false)
        }
        ; Hooked hotkeys suppress Windows' cross-monitor move shortcuts.
        ; Permit one short reentry to latch a new press while Move is waiting.
        ; Busy rejects its operation; the latch also rejects later auto-repeat.
        Hotkey "$#+Left", VDKeyDown.Bind(-1, "Left"), "On T2 B0"
        Hotkey "$#+Right", VDKeyDown.Bind(1, "Right"), "On T2 B0"
        Hotkey "$~*Left Up", VDKeyUp.Bind("Left"), "On"
        Hotkey "$~*Right Up", VDKeyUp.Bind("Right"), "On"
        return true
    }
    catch as err {
        ; Never let an optional DLL prevent unrelated keybind features starting.
        for key in ["$#+Left", "$#+Right", "$~*Left Up", "$~*Right Up"] {
            try Hotkey key, "Off"
        }
        VirtualDesktopState := 0
        VDReport("Virtual desktop shortcuts disabled: " VDErrorText(err))
        return false
    }
}

VirtualDesktopMove(direction) {
    global VirtualDesktopState
    if !IsSet(VirtualDesktopState) || !IsObject(VirtualDesktopState)
        return "disabled"
    return VirtualDesktopState.Controller.Move(direction)
}

VDKeyDown(direction, key, *) {
    global VirtualDesktopState
    if VirtualDesktopState.Held[key]
        return
    VirtualDesktopState.Held[key] := true
    VirtualDesktopMove(direction)
}

VDKeyUp(key, *) {
    global VirtualDesktopState
    VirtualDesktopState.Held[key] := false
}

VDErrorText(err) {
    detail := err.Message
    if err.Extra != ""
        detail .= " | Extra: " err.Extra
    if err.What != ""
        detail .= " | " err.What
    if err.Line
        detail .= " | line " err.Line
    return detail
}

VDReport(message) {
    ; No titles, process command lines, clipboard data or application content.
    OutputDebug "Keybind virtual desktop: " message
    try {
        folder := EnvGet("LOCALAPPDATA") "\keybind"
        DirCreate folder
        path := folder "\virtual-desktop.log"
        if FileExist(path) && FileGetSize(path) > 131072
            FileMove path, path ".old", true
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", path, "UTF-8"
    }
    ToolTip "Keybind: " message
    SetTimer VDHideTip, -4000
}

VDHideTip() {
    ToolTip
}
