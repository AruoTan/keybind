#Include %A_LineFile%/../../virtual-desktop/virtual-desktop.ahk

class PlacementNative {
    __New() {
        this.Windows := VDWindows(), this.Monitors := VDMonitors()
    }
    Valid(token) => this.Windows.Valid(token)
    Same(left, right) => left.Hwnd = right.Hwnd && left.Pid = right.Pid && left.Thread = right.Thread
    WindowMonitor(hwnd) => this.Monitors.Window(hwnd)

    Available() {
        global VirtualDesktopState
        return !IsSet(VirtualDesktopState) || !IsObject(VirtualDesktopState)
            || !VirtualDesktopState.Navigating
    }

    RunDialog(hwnd) {
        return WinGetClass("ahk_id " hwnd) = "#32770"
            && StrLower(WinGetProcessName("ahk_id " hwnd)) = "explorer.exe"
            && !!DllCall("GetDlgItem", "Ptr", hwnd, "Int", 0x3002, "Ptr")
    }

    Inspect(hwnd) {
        ; A process-local hook already decided this window's first-show placement.
        if DllCall("GetPropW", "Ptr", hwnd, "Str", "Keybind.Placement.Done.v1", "Ptr")
            return 0
        if !this.Windows.Ordinary(hwnd) || DllCall("IsIconic", "Ptr", hwnd, "Int")
            || this.Windows.Cloak(hwnd)
            return 0
        ; Leave borderless full-screen apps, including RDP and games, untouched.
        style := WinGetStyle("ahk_id " hwnd)
        if !(style & 0xC00000) {
            wasCritical := A_IsCritical
            Critical "On"
            previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
            try {
                WinGetPos &x, &y, &width, &height, "ahk_id " hwnd
                screen := this.Bounds(this.WindowMonitor(hwnd))
                if x <= screen.Left && y <= screen.Top
                    && x + width >= screen.Right && y + height >= screen.Bottom
                    return 0
            }
            finally {
                if previous
                    DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
                Critical wasCritical
            }
        }
        return {Owner: (root := this.Windows.Owner(hwnd)) = hwnd ? 0 : root}
    }

    Bounds(device) {
        loop MonitorGetCount() {
            if MonitorGetName(A_Index) = device {
                MonitorGet A_Index, &left, &top, &right, &bottom
                return {Left: left, Top: top, Right: right, Bottom: bottom}
            }
        }
        throw Error("Target monitor disconnected")
    }

    Move(token, device) {
        wasCritical := A_IsCritical
        Critical "On"
        previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
        try {
            if !this.Valid(token)
                throw Error("Window identity changed")
            hwnd := token.Hwnd, sourceDevice := this.WindowMonitor(hwnd)
            source := this.Monitors.Work(sourceDevice), target := this.Monitors.Work(device)
            if DllCall("IsZoomed", "Ptr", hwnd, "Int") {
                placement := Buffer(44, 0)
                NumPut "UInt", 44, placement
                if !DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", placement, "Int")
                    throw OSError(, , "Cannot read maximized window placement")
                sourceBounds := this.Bounds(sourceDevice), targetBounds := this.Bounds(device)
                normal := {X: NumGet(placement, 28, "Int") + source.Left - sourceBounds.Left,
                    Y: NumGet(placement, 32, "Int") + source.Top - sourceBounds.Top,
                    Width: NumGet(placement, 36, "Int") - NumGet(placement, 28, "Int"),
                    Height: NumGet(placement, 40, "Int") - NumGet(placement, 32, "Int")}
                rect := PlacementRectangle(normal, source, target)
                x := rect.X - target.Left + targetBounds.Left
                y := rect.Y - target.Top + targetBounds.Top
                NumPut "Int", x, "Int", y, "Int", x + rect.Width, "Int", y + rect.Height, placement, 28
                NumPut "UInt", NumGet(placement, 4, "UInt") | 4, placement, 4 ; WPF_ASYNCWINDOWPLACEMENT
                if !DllCall("SetWindowPlacement", "Ptr", hwnd, "Ptr", placement, "Int")
                    throw OSError(, , "Cannot move maximized window")
            } else {
                WinGetPos &x, &y, &width, &height, "ahk_id " hwnd
                rect := PlacementRectangle({X: x, Y: y, Width: width, Height: height}, source, target)
                if !DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", rect.X, "Int", rect.Y,
                    "Int", 0, "Int", 0, "UInt", 0x4015, "Int") ; ASYNC | NOACTIVATE | NOZORDER | NOSIZE
                    throw OSError(, , "Cannot move application window")
            }
        }
        finally {
            if previous
                DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
            Critical wasCritical
        }
    }
}

PlacementRectangle(rect, source, target) {
    ; Preserve relative placement, fitting the top-left into the target work area.
    x := target.Left + rect.X - source.Left, y := target.Top + rect.Y - source.Top
    return {X: Max(target.Left, Min(x, target.Right - rect.Width)),
        Y: Max(target.Top, Min(y, target.Bottom - rect.Height)), Width: rect.Width, Height: rect.Height}
}
