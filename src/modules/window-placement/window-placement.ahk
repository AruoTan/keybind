; Place windows only before they become visible.
#Include %A_LineFile%/../../virtual-desktop/virtual-desktop.ahk
#Include %A_LineFile%/../bridge.ahk

WindowPlacementInit() {
    global WindowPlacementMonitors, WindowPlacementNative, VirtualDesktopState
    try {
        WindowPlacementMonitors := VDMonitors()
        WindowPlacementNative := PlacementBridge(() => !RemoteDesktopActive())
        try {
            WindowPlacementNative.Start()
            if IsSet(VirtualDesktopState) && IsObject(VirtualDesktopState)
                VirtualDesktopState.PlacementGate := ObjBindMethod(WindowPlacementNative, "Block")
        }
        catch as err {
            WindowPlacementNative.Close()
            PlacementLog("Pre-show unavailable; windows stay in place: " err.Message)
        }
        OnExit WindowPlacementStop
        PlacementLog("Ready; PID=" DllCall("GetCurrentProcessId", "UInt")
            "; mode=pre-show-only; new application windows + Run; Start/Search belong to explorer extension")
    }
    catch as err {
        WindowPlacementStop()
        PlacementLog("Disabled: " err.Message)
    }
}

WindowPlacementStop(*) {
    global WindowPlacementNative
    if IsSet(WindowPlacementNative) && IsObject(WindowPlacementNative)
        WindowPlacementNative.Close()
}

WindowPlacementRun(*) {
    global WindowPlacementMonitors, WindowPlacementNative
    try {
        if IsSet(WindowPlacementNative) && IsObject(WindowPlacementNative)
            && IsSet(WindowPlacementMonitors) && IsObject(WindowPlacementMonitors)
            && WindowPlacementMonitors.Count() > 1
            WindowPlacementNative.RequestRun(WindowPlacementMonitors.Pointer())
    }
    catch as err
        PlacementLog("Run monitor selection failed: " err.Message)
    finally {
        ; Keep the system shortcut working when discovery or native placement fails.
        Send "#r"
    }
}

PlacementLog(message) {
    OutputDebug "Keybind placement: " message
    try {
        folder := EnvGet("LOCALAPPDATA") "\keybind"
        DirCreate folder
        path := folder "\window-placement.log"
        if FileExist(path) && FileGetSize(path) > 131072
            FileMove path, path ".old", true
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", path, "UTF-8"
    }
}
