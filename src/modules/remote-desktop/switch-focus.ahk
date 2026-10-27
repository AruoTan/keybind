; A desktop GUID change alone does not transfer keyboard focus out of RDP.
; Use real window activation, never clicks, Alt+Tab or modifier injection.
class RDPFocusHistory {
    __New() {
        this.Windows := Map()
    }

    Remember(api, windows, desktop, hwnd) {
        try {
            if !hwnd || !windows.Ordinary(hwnd) || WinGetMinMax("ahk_id " hwnd) = -1
                || api.WindowId(hwnd) != desktop || api.Pinned(hwnd)
                return
            token := windows.Token(hwnd)
            isRdp := WinGetProcessName("ahk_id " hwnd) = "msrdc.exe"
                || (WinGetProcessName("ahk_id " hwnd) = "mstsc.exe"
                    && WinGetClass("ahk_id " hwnd) = "TscShellContainerClass")
            if this.Windows.Has(desktop)
                this.Windows.Delete(desktop)
            this.Windows[desktop] := {Token: token, Rdp: isRdp}
            if this.Windows.Count > 64 {
                for id in this.Windows {
                    this.Windows.Delete(id)
                    break
                }
            }
        }
    }

    Get(api, windows, desktop) {
        if !this.Windows.Has(desktop)
            return 0
        remembered := this.Windows[desktop]
        try {
            if windows.Valid(remembered.Token) && api.WindowId(remembered.Token.Hwnd) = desktop
                && !api.Pinned(remembered.Token.Hwnd)
                return remembered
        }
        this.Windows.Delete(desktop)
        return 0
    }
}

class RDPSwitchFocus {
    __New(origin, windows := 0, history := 0) {
        this.Origin := origin
        this.Windows := IsObject(windows) ? windows : VDWindows()
        this.History := IsObject(history) ? history : RDPFocusHistory()
        this.Broker := 0
        this.Switched := false
        this.Candidates := []
        this.SourceToken := 0
    }

    Before(api, source, target) {
        if DllCall("GetForegroundWindow", "Ptr") != this.Origin
            throw Error("Foreground changed before RDP focus handoff")
        if this.Windows.Ordinary(this.Origin)
            this.SourceToken := this.Windows.Token(this.Origin)
        this.History.Remember(api, this.Windows, source, this.Origin)
        ; Preserve Z order and skip minimized windows. Merely switching must
        ; not restore minimized apps or move a window from another desktop.
        for token in this.Windows.Applications() {
            if token.Hwnd = this.Origin
                continue
            try {
                if this.Eligible(api, token, target)
                    this.Candidates.Push(token)
            }
        }
        this.Broker := Gui("+ToolWindow -Caption", "Keybind input handoff")
        this.Broker.AddEdit("w1 h1")
        this.Broker.Show("NoActivate x" SysGet(76) " y" SysGet(77) " w1 h1")
        if !this.Activate(this.Broker.Hwnd)
            throw Error("Cannot deactivate RDP before desktop switch")
        RemoteDesktopLog("Source focus released before switch; " this.Describe())
    }

    SourceOccupied(api, source) {
        token := this.SourceToken
        if !IsObject(token) || !this.Windows.Valid(token)
            return false
        try {
            if api.Pinned(token.Hwnd)
                return false
            location := api.WindowId(token.Hwnd)
            return this.Windows.Valid(token) && location = source
        }
        catch as err {
            if this.Windows.Valid(token)
                throw Error("Source desktop occupancy check failed: " VDErrorText(err), ,
                    this.Windows.Describe(token))
            return false
        }
    }

    Eligible(api, token, target) {
        return this.Windows.Valid(token) && this.Windows.Ordinary(token.Hwnd, true)
            && WinGetMinMax("ahk_id " token.Hwnd) != -1
            && DllCall("IsWindowEnabled", "Ptr", token.Hwnd, "Int")
            && (api.WindowId(token.Hwnd) = target || api.Pinned(token.Hwnd))
    }

    After(api, source, target) {
        this.Switched := true
        if api.Current() != target
            return false
        remembered := this.History.Get(api, this.Windows, target)
        if IsObject(remembered) {
            token := remembered.Token
            try {
                if remembered.Rdp
                    this.ShowRemembered(api, token, target)
                if this.Eligible(api, token, target) && this.Activate(token.Hwnd) {
                    RemoteDesktopLog("Remembered desktop window activated; " this.Describe())
                    return true
                }
            }
        }
        ; The shell may have selected a suitable window itself. Re-activate it
        ; once to complete input focus rather than accepting its HWND alone.
        foreground := DllCall("GetForegroundWindow", "Ptr")
        if foreground && foreground != this.Origin && foreground != this.Broker.Hwnd {
            try {
                if this.Eligible(api, this.Windows.Token(foreground), target)
                    && this.Activate(foreground) {
                    RemoteDesktopLog("Local application focus restored; " this.Describe())
                    return true
                }
            }
        }
        for token in this.Candidates {
            if api.Current() != target
                return false
            try {
                if this.Eligible(api, token, target) && this.Activate(token.Hwnd) {
                    RemoteDesktopLog("Target desktop application activated; " this.Describe())
                    return true
                }
            }
        }
        ; Empty desktops still need a local foreground input owner so native
        ; Win+Ctrl, Win+E, Win+S and ordinary keyboard input can keep working.
        for shell in this.ShellWindows() {
            if api.Current() != target
                return false
            if this.Activate(shell) {
                RemoteDesktopLog("Local shell focus restored; " this.Describe())
                return true
            }
        }
        RemoteDesktopLog("Desktop switched but local focus handoff failed; " this.Describe())
        return false
    }

    ShowRemembered(api, token, target) {
        ; RDP can hide/minimize its fullscreen session on deactivation. Restore
        ; only its remembered HWND, without a fullscreen toggle or style change.
        show := DllCall("IsIconic", "Ptr", token.Hwnd, "Int") ? 9 : 5
        DllCall("ShowWindowAsync", "Ptr", token.Hwnd, "Int", show, "Int")
        started := A_TickCount
        loop {
            if !this.Windows.Valid(token) || api.Current() != target
                return
            if DllCall("IsWindowVisible", "Ptr", token.Hwnd, "Int")
                && !DllCall("IsIconic", "Ptr", token.Hwnd, "Int")
                return
            if A_TickCount - started >= 300
                return
            Sleep 10
        }
    }

    ShellWindows() {
        return [WinExist("ahk_class Shell_TrayWnd"), DllCall("GetShellWindow", "Ptr")]
    }

    Activate(hwnd, timeout := 300) {
        if !hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")
            return false
        DllCall("SetForegroundWindow", "Ptr", hwnd, "Int")
        started := A_TickCount
        loop {
            if DllCall("GetForegroundWindow", "Ptr") = hwnd
                return true
            if A_TickCount - started >= timeout
                return false
            Sleep 10
        }
    }

    Describe() {
        ; GUITHREADINFO x64: cbSize/flags + six HWNDs + RECT = 72 bytes.
        info := Buffer(8 + 6 * A_PtrSize + 16, 0)
        NumPut "UInt", info.Size, info
        if !DllCall("GetGUIThreadInfo", "UInt", 0, "Ptr", info, "Int")
            return "foreground=" DllCall("GetForegroundWindow", "Ptr") "; input-focus=unknown"
        return "foreground=" NumGet(info, 8, "Ptr") "; input-focus=" NumGet(info, 8 + A_PtrSize, "Ptr")
    }

    Close() {
        if IsObject(this.Broker) {
            if !this.Switched && DllCall("GetForegroundWindow", "Ptr") = this.Broker.Hwnd
                this.Activate(this.Origin)
            this.Broker.Destroy()
            this.Broker := 0
        }
    }
}
