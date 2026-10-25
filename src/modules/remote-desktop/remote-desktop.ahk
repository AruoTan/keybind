; Keep the four desktop-navigation shortcuts on the RDP client machine.
; Other Win combinations remain available to the remote session.
#Include %A_LineFile%/../keyboard-hook.ahk
#Include %A_LineFile%/../switch-focus.ahk

RemoteDesktopInit() {
    global RemoteDesktopGuard, RemoteDesktopHook, RemoteDesktopHistory
    try {
        RemoteDesktopHook := RDPKeyboardHook()
        RemoteDesktopHistory := RDPFocusHistory()
        OnMessage RemoteDesktopHook.Message, RemoteDesktopDispatch, 2
        OnExit RemoteDesktopStop
        RemoteDesktopGuard := RDPHookGuard()
        SetTimer RemoteDesktopRefresh, 100
        RemoteDesktopHook.Reinstall() ; Ctrl+Win also works before entering RDP.
        RemoteDesktopLog("Initialized physical keyboard hook v8 continuous navigation; mstsc + msrdc; AHK " A_AhkVersion
            "; PID " DllCall("GetCurrentProcessId", "UInt") "; admin=" A_IsAdmin)
        RemoteDesktopRefresh()
        return true
    }
    catch as err {
        RemoteDesktopStop()
        VDReport("Local RDP shortcuts disabled: " VDErrorText(err))
        return false
    }
}

RemoteDesktopActive(*) {
    ; Windows App uses msrdc.exe for its desktop sessions. Its launcher
    ; msrdcw.exe is deliberately excluded, as are arbitrary UWP frame hosts.
    ; Do not require mstsc's window class for the Windows App client.
    if hwnd := WinActive("ahk_exe msrdc.exe")
        return hwnd
    return WinActive("ahk_class TscShellContainerClass ahk_exe mstsc.exe")
}

RemoteDesktopSignature() {
    hwnd := RemoteDesktopActive()
    if !hwnd
        return ""
    try {
        ; Detect windowed/fullscreen transitions as well as a different session.
        WinGetPos &x, &y, &width, &height, "ahk_id " hwnd
        return WinGetProcessName("ahk_id " hwnd) ":" WinGetClass("ahk_id " hwnd) ":"
            . hwnd ":" WinGetStyle("ahk_id " hwnd) ":" x ":" y ":" width ":" height
    }
    catch {
        return "" ; A session may close between foreground and bounds queries.
    }
}

RemoteDesktopDispatch(serial, lParam, message, hwnd) {
    global RemoteDesktopHook, RemoteDesktopHistory
    if !RemoteDesktopHook.Requests.Has(serial)
        return ; Only dispatch requests actually captured by this hook.
    request := RemoteDesktopHook.Requests.Delete(serial)
    move := request.Action >= 3
    if request.Window != DllCall("GetForegroundWindow", "Ptr")
        || (move && request.Window != RemoteDesktopActive()) {
        RemoteDesktopLog("Captured shortcut skipped after focus changed")
        return
    }
    direction := Mod(request.Action, 2) ? -1 : 1
    RemoteDesktopHook.Working := true
    try {
        RemoteDesktopLog("Captured " (move ? "move " : "switch ") (direction = -1 ? "Left" : "Right"))
        result := move ? VirtualDesktopMove(direction)
            : VirtualDesktopSwitch(direction, RDPSwitchFocus(request.Window, 0, RemoteDesktopHistory))
        RemoteDesktopLog("Hotkey " (move ? "move " : "switch ") (direction = -1 ? "Left" : "Right") ": " result)
    }
    finally RemoteDesktopHook.Working := false
}

RemoteDesktopStop(*) {
    global RemoteDesktopHook
    SetTimer RemoteDesktopRefresh, 0
    if IsSet(RemoteDesktopHook) && IsObject(RemoteDesktopHook) {
        OnMessage RemoteDesktopHook.Message, RemoteDesktopDispatch, 0
        RemoteDesktopHook.Close()
    }
}

RemoteDesktopLog(message) {
    ; Only initialization, window class/geometry and these four hotkey results.
    ; Never record titles, addresses, ordinary keystrokes or remote contents.
    OutputDebug "Keybind RDP: " message
    try {
        folder := EnvGet("LOCALAPPDATA") "\keybind"
        DirCreate folder
        path := folder "\remote-desktop.log"
        if FileExist(path) && FileGetSize(path) > 131072
            FileMove path, path ".old", true
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", path, "UTF-8"
    }
}

RemoteDesktopKeysDown() {
    ; Do not reinstall a hook in the middle of a physical chord. The native
    ; state is only an extra guard; recognition uses the hook's own events.
    for vk in [0x10, 0x11, 0x12, 0x5B, 0x5C, 0x25, 0x27] {
        if DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000
            return true
    }
    return false
}

RemoteDesktopRefresh() {
    global RemoteDesktopGuard, RemoteDesktopHook
    try {
        now := A_TickCount
        nativeKeysDown := RemoteDesktopKeysDown()
        RemoteDesktopHook.ObserveWindow(RemoteDesktopActive(), now, nativeKeysDown)
        if RemoteDesktopHook.Fault != "" {
            RemoteDesktopLog("Hook error: " RemoteDesktopHook.Fault)
            RemoteDesktopHook.Fault := ""
        }
        if RemoteDesktopHook.Probe != "" {
            RemoteDesktopLog(RemoteDesktopHook.Probe)
            RemoteDesktopHook.Probe := ""
        }
        ; Formatting/file IO stay out of the keyboard callback. Capture both
        ; physical and ignored injected modifier transitions to locate lost up.
        rejected := RemoteDesktopHook.Rejected
        RemoteDesktopHook.Rejected := []
        for report in rejected {
            detail := "Rejected chord tick=" report.Tick "; " report.Summary "; state=" report.State
            for event in report.Events
                detail .= "`n  Modifier " event
            RemoteDesktopLog(detail)
        }
        ; A missed key-up must never make our recorded Down map a permanent
        ; veto on the very refresh needed to receive future key-up events.
        RemoteDesktopGuard.Update(RemoteDesktopSignature(), now, nativeKeysDown)
    }
    catch as err {
        SetTimer RemoteDesktopRefresh, 0
        VDReport("RDP keyboard hook refresh stopped: " VDErrorText(err))
    }
}

class RDPHookGuard {
    __New(reinstall := RDPReinstallHook) {
        this.Reinstall := reinstall
        this.Signature := ""
        this.Pending := false
        this.RetryAt := 0
        this.BlockedAt := -1
    }

    Update(signature, now, keysDown) {
        if signature != this.Signature {
            this.Signature := signature
            this.Pending := signature != ""
            this.RetryAt := 0
            this.BlockedAt := -1
            RemoteDesktopLog(signature = "" ? "Session inactive" : "Session active: " signature)
        }
        if signature = ""
            return
        if keysDown {
            if this.BlockedAt < 0
                this.BlockedAt := now
            if now - this.BlockedAt < 500
                return
        } else
            this.BlockedAt := -1
        if this.Pending {
            if keysDown
                RemoteDesktopLog("Key-state wait expired; refreshing with chord state preserved")
            this.Reinstall.Call()
            this.Pending := false
            ; mstsc can install its hook after activation/fullscreen entry.
            this.RetryAt := now + 500
        }
        else if this.RetryAt && now >= this.RetryAt {
            if keysDown
                RemoteDesktopLog("Key-state wait expired; refreshing with chord state preserved")
            this.Reinstall.Call()
            ; Fullscreen clients may take priority again after our initial
            ; activation refresh. Reclaim it while no physical key is held.
            this.RetryAt := now + 1000
        }
    }
}

RDPReinstallHook() {
    global RemoteDesktopHook
    RemoteDesktopHook.Reinstall()
    RemoteDesktopLog("Physical keyboard hook refreshed")
}
