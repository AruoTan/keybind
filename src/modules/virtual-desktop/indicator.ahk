#Include %A_LineFile%/../indicator-render.ahk

; Final desktop position, shown only after navigation and source cleanup finish.
class VDIndicator {
    __New(duration := 1000, viewport := VDIndicatorViewport) {
        this.Duration := duration
        this.Viewport := viewport
        this.Window := 0
        this.Shadow := 0
        this.Text := ""
        this.Deadline := 0
        this.Revision := 0
        this.Timer := this.Expire.Bind(this)
    }

    Begin() {
        this.Revision += 1
        this.Close()
        return this.Revision
    }

    Complete(api, result, revision := -1) {
        if !RegExMatch(result, "^(moved|moved-retained|switched|switched-retained|switched-unfocused)$")
            return false
        if revision < 0
            revision := this.Revision
        ; Never reuse the target's index from before the source was removed.
        desktop := api.Current()
        number := api.Index(desktop) + 1
        if api.Current() != desktop || this.Revision != revision
            return false
        return this.Show(number, revision)
    }

    Warmup() {
        VDIndicatorGraphics()
        work := {Left: 0, Top: 0, Right: A_ScreenWidth, Bottom: A_ScreenHeight}
        layout := VDIndicatorLayout(work, A_ScreenDPI)
        light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "SystemUsesLightTheme", 1)
        this.Prepare(layout, "桌面 1", light)
    }

    Prepare(layout, text, light) {
        ; Pixel loops and font rendering run with normal message processing.
        return {Card: VDIndicatorCachedCard(layout, text, light), Shadow: VDIndicatorCachedShadow(layout)}
    }

    Show(number, revision := -1) {
        if revision < 0
            revision := this.Revision
        if revision != this.Revision
            return false
        candidate := 0, shadow := 0, committed := false
        wasCritical := A_IsCritical
        previous := 0
        try {
            ; Only the short HWND/DPI transactions are atomic. Never hold
            ; Critical across pixel generation, GDI+ startup or font rendering.
            Critical "On"
            try {
                previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
                work := this.Viewport.Call()
                candidate := Gui("+AlwaysOnTop +ToolWindow -Caption -Border -DPIScale +E0x08080020",
                    "Keybind desktop indicator")
                hwnd := candidate.Hwnd
                if !DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", work.Left,
                    "Int", work.Top, "Int", 0, "Int", 0, "UInt", 0x15, "Int")
                    throw OSError(, , "Cannot position desktop indicator")
                dpi := work.HasOwnProp("Dpi") ? work.Dpi : DllCall("GetDpiForWindow", "Ptr", hwnd, "UInt")
                layout := VDIndicatorLayout(work, dpi ? dpi : A_ScreenDPI)
            }
            finally {
                if previous
                    DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
                previous := 0
                Critical wasCritical
            }
            light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                "SystemUsesLightTheme", 1)
            text := "桌面 " number
            prepared := this.Prepare(layout, text, light)
            Critical "On"
            try {
                ; A later request can supersede this one while Prepare runs.
                if revision != this.Revision
                    return false
                previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
                this.Close()
                VDIndicatorUpdateImage(candidate, prepared.Card, layout.X, layout.Y)
                try shadow := VDIndicatorCreateShadow(layout, prepared.Shadow)
                catch as err
                    VDLog("Desktop indicator shadow failed: " VDErrorText(err))
                candidate.Show("NoActivate x" layout.X " y" layout.Y
                    " w" layout.Width " h" layout.Height)
                if IsObject(shadow) && !DllCall("SetWindowPos", "Ptr", shadow.Hwnd,
                    "Ptr", hwnd, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13, "Int") {
                    shadow.Destroy()
                    shadow := 0
                    VDLog("Desktop indicator shadow ordering failed; card retained")
                }
                this.Window := candidate
                this.Shadow := shadow
                this.Text := text
                this.Deadline := A_TickCount + this.Duration
                SetTimer this.Timer, -this.Duration
                committed := true
                return true
            }
            finally {
                if previous
                    DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
                previous := 0
                Critical wasCritical
            }
        }
        finally {
            if !committed {
                if IsObject(shadow)
                    shadow.Destroy()
                if IsObject(candidate)
                    candidate.Destroy()
            }
        }
    }

    Expire(*) {
        remaining := this.Deadline - A_TickCount
        if remaining > 0 {
            SetTimer this.Timer, -remaining
            return
        }
        this.Close()
    }

    Close(*) {
        wasCritical := A_IsCritical
        Critical "On"
        try {
            SetTimer this.Timer, 0
            this.Deadline := 0
            if IsObject(this.Shadow)
                this.Shadow.Destroy()
            this.Shadow := 0
            if IsObject(this.Window)
                this.Window.Destroy()
            this.Window := 0
            this.Text := ""
        }
        finally Critical wasCritical
    }

}

VDIndicatorViewport() {
    foreground := DllCall("GetForegroundWindow", "Ptr")
    monitor := DllCall("MonitorFromWindow", "Ptr", foreground, "UInt", 2, "Ptr")
    info := Buffer(40, 0)
    NumPut "UInt", info.Size, info
    if !DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", info, "Int")
        throw OSError(, , "Cannot locate desktop indicator monitor")
    return {Left: NumGet(info, 20, "Int"), Top: NumGet(info, 24, "Int"),
        Right: NumGet(info, 28, "Int"), Bottom: NumGet(info, 32, "Int")}
}

VDIndicatorLayout(work, dpi) {
    scale := dpi / 96
    width := Min(Round(128 * scale), work.Right - work.Left)
    height := Min(Round(48 * scale), work.Bottom - work.Top)
    if width <= 0 || height <= 0
        throw Error("Invalid desktop indicator work area")
    return {X: work.Left + Floor((work.Right - work.Left - width) / 2),
        Y: Max(work.Top, work.Bottom - height - Round(16 * scale)),
        Width: width, Height: height, Scale: scale, Radius: Round(8 * scale), FontHeight: Round(14 * scale)}
}
