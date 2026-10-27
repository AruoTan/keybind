; Application-window classification, ownership and focus.
class VDWindows {
    Token(hwnd) {
        pid := 0
        thread := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
        if !thread || !pid
            throw Error("Cannot identify application window")
        return {Hwnd: hwnd, Pid: pid, Thread: thread}
    }

    Valid(token) {
        if !DllCall("IsWindow", "Ptr", token.Hwnd, "Int")
            return false
        pid := 0
        thread := DllCall("GetWindowThreadProcessId", "Ptr", token.Hwnd, "UInt*", &pid, "UInt")
        return pid = token.Pid && thread = token.Thread
    }

    Describe(token) {
        classBuffer := Buffer(512, 0)
        className := DllCall("GetClassNameW", "Ptr", token.Hwnd, "Ptr", classBuffer,
            "Int", 256, "Int") ? StrGet(classBuffer, "UTF-16") : "unknown"
        ; Identify a cleanup blocker without logging its title or app contents.
        cloak := "unknown"
        try cloak := Format("0x{:X}", this.Cloak(token.Hwnd))
        frame := ""
        try {
            state := this.FrameState(token)
            if IsObject(state)
                frame := Format("; core-window {}; foreground {}", state.CoreWindow, state.Foreground)
        }
        return Format("HWND 0x{:X}; PID {}; class {}; cloak {}; minimized {}",
            token.Hwnd, token.Pid, className, cloak,
            !!DllCall("IsIconic", "Ptr", token.Hwnd, "Int")) frame
    }

    Cloak(hwnd) {
        flags := 0
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14,
            "UInt*", &flags, "UInt", 4, "Int") ; DWMWA_CLOAKED
        if hr != 0
            throw Error("Cannot query window cloak state", , Format("HRESULT 0x{:08X}", hr & 0xFFFFFFFF))
        return flags
    }

    FrameState(token) {
        previous := A_DetectHiddenWindows
        DetectHiddenWindows true
        try {
            criteria := "ahk_id " token.Hwnd
            if WinGetClass(criteria) != "ApplicationFrameWindow"
                || StrLower(WinGetProcessName(criteria)) != "applicationframehost.exe"
                return 0
            coreWindow := false
            for child in WinGetControlsHwnd(criteria) {
                if WinGetClass("ahk_id " child) = "Windows.UI.Core.CoreWindow" {
                    coreWindow := true
                    break
                }
            }
            return {Cloak: this.Cloak(token.Hwnd), CoreWindow: coreWindow,
                Minimized: !!DllCall("IsIconic", "Ptr", token.Hwnd, "Int"),
                Foreground: DllCall("GetForegroundWindow", "Ptr") = token.Hwnd}
        }
        finally DetectHiddenWindows previous
    }

    UntrackedFrame(token, err) {
        ; Never interpret a generic query failure or GUID_NULL as an empty
        ; frame. TYPE_E_ELEMENTNOTFOUND must refer to this exact window.
        if !(err is VDWindowQueryError) || err.HResult != 0x8002802B
            || err.Hwnd != token.Hwnd || !this.Valid(token)
            return false
        state := this.FrameState(token)
        ; A parked frame is app-cloaked, not shell-cloaked by another desktop.
        ; Keep minimized frames, active frames and frames hosting a UWP view.
        return IsObject(state) && state.Cloak = 1 && !state.CoreWindow
            && !state.Minimized && !state.Foreground && this.Valid(token)
    }

    All() {
        previous := A_DetectHiddenWindows
        DetectHiddenWindows true
        try return WinGetList()
        finally DetectHiddenWindows previous
    }

    System(hwnd) {
        classBuffer := Buffer(512, 0)
        if !DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", classBuffer, "Int", 256, "Int")
            throw Error("Cannot classify window")
        className := StrGet(classBuffer, "UTF-16")
        if RegExMatch(className, "i)^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd|"
            "MultitaskingViewFrame|XamlExplorerHostIslandWindow|"
            "tooltips_class32|#32768|NotifyIconOverflowWindow)$")
            || hwnd = DllCall("GetShellWindow", "Ptr")
            || hwnd = DllCall("GetDesktopWindow", "Ptr")
            return true
        ; CoreWindow is also used by real UWP apps; exclude only shell hosts.
        previous := A_DetectHiddenWindows
        DetectHiddenWindows true
        try return RegExMatch(WinGetProcessName("ahk_id " hwnd),
                "i)^(StartMenuExperienceHost|ShellExperienceHost|SearchHost|SearchApp|TextInputHost|LockApp)\.exe$")
        finally DetectHiddenWindows previous
    }

    Ordinary(hwnd, owned := false) {
        if !DllCall("IsWindow", "Ptr", hwnd, "Int")
            return false
        ; WS_VISIBLE remains set for minimized and DWM-cloaked desktop windows.
        ; Do not exclude all cloaked windows: other-desktop apps are cloaked too.
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int") || this.System(hwnd)
            return false
        style := DllCall("GetWindowLongPtrW", "Ptr", hwnd, "Int", -16, "Ptr")
        exStyle := DllCall("GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
        if (style & 0x40000000) || (exStyle & 0x08000000)
            return false ; WS_CHILD / WS_EX_NOACTIVATE
        if !owned && (exStyle & 0x80) && !(exStyle & 0x40000)
            return false ; Tool windows, unless explicitly marked APPWINDOW.
        return true
    }

    Applications() {
        result := []
        for hwnd in this.All() {
            try {
                if this.Ordinary(hwnd)
                    result.Push(this.Token(hwnd))
            }
            catch as err {
                ; A disappeared window is harmless; any live unknown blocks cleanup.
                if DllCall("IsWindow", "Ptr", hwnd, "Int")
                    throw err
            }
        }
        return result
    }

    Capture() {
        active := DllCall("GetForegroundWindow", "Ptr")
        if !active || this.System(active)
            return 0
        root := DllCall("GetAncestor", "Ptr", active, "UInt", 3, "Ptr") ; GA_ROOTOWNER
        if !root || !this.Ordinary(root) || !this.Ordinary(active)
            return 0
        main := this.Token(root)
        group := {Root: main, Active: this.Token(active), Members: [main]}
        for hwnd in this.All() {
            if hwnd != root && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 3, "Ptr") = root
                && this.Ordinary(hwnd, true)
                group.Members.Push(this.Token(hwnd))
        }
        return group
    }

    StillActive(group) => this.Valid(group.Active)
        && DllCall("GetForegroundWindow", "Ptr") = group.Active.Hwnd

    Focus(group) {
        token := this.Valid(group.Active) ? group.Active : group.Root
        if !this.Valid(token)
            return false
        try {
            WinActivate "ahk_id " token.Hwnd
            return !!WinWaitActive("ahk_id " token.Hwnd, , 0.5)
        }
        catch
            return false
    }
}
