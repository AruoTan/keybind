; Dynamic virtual desktop entry points and keyboard registration.
#Include %A_LineFile%/../controller.ahk
#Include %A_LineFile%/../native.ahk
#Include %A_LineFile%/../windows.ahk
#Include %A_LineFile%/../indicator.ahk

; AutoHotkey v2, Windows x64. Including this file alone registers no hotkeys.
VirtualDesktopInit() {
    global VirtualDesktopState
    VDLog("Virtual desktop init; diagnostics=cleanup-v2; PID=" DllCall("GetCurrentProcessId", "UInt")
        "; executable=" A_ScriptFullPath)
    try {
        dll := A_IsCompiled ? A_ScriptDir "\VirtualDesktopAccessor.dll"
            : A_ScriptDir "\..\dist\windows-x64\VirtualDesktopAccessor.dll"
        api := VDNative(dll)
        api.Snapshot() ; Includes GUID ABI and index round-trip checks.
        api.Current()
        VirtualDesktopState := {
            Controller: VDController(api, VDWindows()), Held: Map("Left", false, "Right", false),
            Indicator: VDIndicator()
        }
        ; Warm the common card before installing navigation hooks, so the
        ; first switch does not pay for DLL startup and initial font loading.
        try VirtualDesktopState.Indicator.Warmup()
        catch as err
            VDLog("Desktop indicator warmup failed: " VDErrorText(err))
        VDLog("Desktop indicator renderer; diagnostics=resident-cache-v1")
        ; Hooked hotkeys suppress Windows' cross-monitor move shortcuts.
        ; Permit one short reentry to latch a new press while Move is waiting.
        ; Busy rejects its operation; the latch also rejects later auto-repeat.
        Hotkey "$#+Left", VDKeyDown.Bind(-1, "Left"), "On T2 B0"
        Hotkey "$#+Right", VDKeyDown.Bind(1, "Right"), "On T2 B0"
        Hotkey "$~*Left Up", VDKeyUp.Bind("Left"), "On"
        Hotkey "$~*Right Up", VDKeyUp.Bind("Right"), "On"
        OnExit VDCloseIndicator
        VDLog("Virtual desktop ready; diagnostics=cleanup-v2")
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
    if !IsSet(VirtualDesktopState) || !IsObject(VirtualDesktopState) {
        VDLog("Operation result; action=move; direction=" direction "; result=disabled")
        return "disabled"
    }
    return VDNavigateWithIndicator(VirtualDesktopState, true, direction)
}

VirtualDesktopSwitch(direction, focus := 0) {
    global VirtualDesktopState
    if !IsSet(VirtualDesktopState) || !IsObject(VirtualDesktopState) {
        VDLog("Operation result; action=switch; direction=" direction "; result=disabled")
        return "disabled"
    }
    return VDNavigateWithIndicator(VirtualDesktopState, false, direction, focus)
}

VDNavigateWithIndicator(state, move, direction, focus := 0) {
    indicator := state.HasOwnProp("Indicator") ? state.Indicator : 0
    revision := -1
    if IsObject(indicator) && !state.Controller.Busy {
        try revision := indicator.Begin()
        catch as err
            VDLog("Desktop indicator reset failed: " VDErrorText(err))
    }
    result := move ? state.Controller.Move(direction) : state.Controller.Switch(direction, focus)
    if IsObject(indicator) && revision >= 0 {
        try indicator.Complete(state.Controller.Api, result, revision)
        catch as err
            VDLog("Desktop indicator failed: " VDErrorText(err))
    }
    return result ; A display failure must never turn navigation into a failure.
}

VDCloseIndicator(*) {
    global VirtualDesktopState
    if IsSet(VirtualDesktopState) && IsObject(VirtualDesktopState)
        && VirtualDesktopState.HasOwnProp("Indicator")
        VirtualDesktopState.Indicator.Close()
}

VDSwitchKeyDown(direction, key, *) {
    global VirtualDesktopState
    if VirtualDesktopState.Held[key]
        return "held"
    VirtualDesktopState.Held[key] := true
    return VirtualDesktopSwitch(direction)
}

VDKeyDown(direction, key, *) {
    global VirtualDesktopState
    if VirtualDesktopState.Held[key]
        return "held"
    VirtualDesktopState.Held[key] := true
    return VirtualDesktopMove(direction)
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
    VDLog(message)
    ToolTip "Keybind: " message
    SetTimer VDHideTip, -4000
}

VDLog(message) {
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
}

VDHideTip() {
    ToolTip
}
