#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk

logPath := A_Args[1]
indicator := 0, main := 0
CoordMode "Mouse", "Screen"
MouseGetPos &savedX, &savedY
try {
    LayoutTests()
    AntialiasTests()
    RendererLifetimeTests()
    main := Gui(, "Keybind indicator input fixture")
    clicks := []
    button := main.AddButton("x0 y0 w400 h200", "Click-through target")
    button.OnEvent("Click", (*) => clicks.Push(true))
    inputField := main.AddEdit("x10 y10 w280 h30")
    main.Show("x100 y100 w400 h200")
    WinActivate "ahk_id " main.Hwnd
    if !WinWaitActive("ahk_id " main.Hwnd, , 1)
        throw Error("Cannot activate indicator input fixture")
    inputField.Focus()
    WinGetClientPos &x, &y, &width, &height, "ahk_id " main.Hwnd
    work := {Left: x, Top: y, Right: x + width, Bottom: y + height, Dpi: 96}
    indicator := VDIndicator(2000, () => work)
    indicator.Show(1)
    hwnd := indicator.Window.Hwnd
    Check(DllCall("GetForegroundWindow", "Ptr") = main.Hwnd, "Showing the card must not change foreground")
    Check(indicator.Text = "桌面 1", "Render the final desktop number")
    style := DllCall("GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
    Check((style & 0x080800A8) = 0x080800A8,
        "Indicator must be noactivate, layered, transparent, a tool window and topmost")
    Check(!VDWindows().Ordinary(hwnd), "The indicator must not count as an application or block cleanup")
    shadowHwnd := indicator.Shadow.Hwnd
    Check(!VDWindows().Ordinary(shadowHwnd), "The shadow must not count as a desktop application")
    shadowStyle := DllCall("GetWindowLongPtrW", "Ptr", shadowHwnd, "Int", -20, "Ptr")
    Check((shadowStyle & 0x080800A8) = 0x080800A8,
        "The shadow must preserve click-through, noactivation and tool-window behavior")
    WinGetPos &px, &py, &pw, &ph, "ahk_id " hwnd
    expected := VDIndicatorLayout(work, 96)
    shadowImage := VDIndicatorShadowImage(expected)
    sampleX := shadowImage.Width // 2
    Check(NumGet(shadowImage.Pixels, (shadowImage.Height // 2 * shadowImage.Width + sampleX) * 4,
        "UInt") = 0, "Shadow pixels under the card must remain transparent")
    nearEdge := NumGet(shadowImage.Pixels,
        ((shadowImage.Padding + expected.Height + 1) * shadowImage.Width + sampleX) * 4 + 3, "UChar")
    farEdge := NumGet(shadowImage.Pixels,
        ((shadowImage.Height - 1) * shadowImage.Width + sampleX) * 4 + 3, "UChar")
    Check(nearEdge > 0 && farEdge = 0, "The shadow must fade completely before the bitmap boundary")
    Check(px = expected.X && py = expected.Y && pw = 128 && ph = 48,
        "The visible card must use physical pixels and stay inside the selected work area")
    region := DllCall("gdi32\CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    try Check(DllCall("GetWindowRgn", "Ptr", hwnd, "Ptr", region, "Int") = 0,
        "Per-pixel corners must not be clipped by a binary window region")
    finally DllCall("gdi32\DeleteObject", "Ptr", region)
    SendInput "a"
    Sleep 30
    Check(inputField.Value = "a", "Typing must still reach the application under the card")
    Click px + pw // 2, py + ph // 2
    Sleep 50
    Check(clicks.Length = 1, "A real click through the card must reach the underlying application's button")
    Click px + pw // 2, py + ph + 2
    Sleep 50
    Check(clicks.Length = 2, "A click through the shadow edge must reach the underlying application")
    Check(DllCall("GetForegroundWindow", "Ptr") = main.Hwnd, "A click must not activate the indicator")

    indicator.Duration := 600
    indicator.Show(2)
    old := indicator.Window.Hwnd
    Sleep 300
    indicator.Show(3)
    Check(!DllCall("IsWindow", "Ptr", old, "Int"), "Retire the earlier desktop's HWND")
    Check(indicator.Text = "桌面 3", "A later switch replaces the earlier number")
    Sleep 400
    Check(IsObject(indicator.Window), "An earlier hide timer must not dismiss the newer card")
    WaitFor(() => !IsObject(indicator.Window))
    Check(indicator.Text = "" && !IsObject(indicator.Shadow)
        && !DllCall("IsWindow", "Ptr", shadowHwnd, "Int"),
        "Automatic dismissal must release the card and shadow")
    indicator.Show(4)
    indicator.Close()
    indicator.Close()
    Check(!IsObject(indicator.Window) && indicator.Text = "", "Explicit cleanup must be repeatable")
    indicator := VDIndicator()
    context := DllCall("GetThreadDpiAwarenessContext", "Ptr")
    indicator.Show(5)
    Check(DllCall("AreDpiAwarenessContextsEqual", "Ptr", context,
        "Ptr", DllCall("GetThreadDpiAwarenessContext", "Ptr"), "Int"),
        "Creating the indicator must restore the thread's DPI awareness")
    Check(DllCall("GetForegroundWindow", "Ptr") = main.Hwnd,
        "The default monitor/DPI path must also preserve the foreground")
    viewport := VDIndicatorViewport()
    WinGetPos &px, &py, &pw, &ph, "ahk_id " indicator.Window.Hwnd
    Check(px >= viewport.Left && py >= viewport.Top && px + pw <= viewport.Right
        && py + ph <= viewport.Bottom, "The default viewport must position the card inside the work area")
    indicator.Close()
    indicator := InterruptibleIndicator(2000, () => work)
    indicator.Show(1)
    Check(indicator.PreparedCritical = 0, "Expensive rendering must not run in Critical")
    indicator.Close()
    indicator.Supersede := true
    Check(!indicator.Show(2) && !IsObject(indicator.Window),
        "A superseded render must discard its temporary window without publishing it")
    indicator.Supersede := false
    indicator.Show(1)
    indicator.Close()
    process := DllCall("GetCurrentProcess", "Ptr")
    initialGdi := DllCall("GetGuiResources", "Ptr", process, "UInt", 0, "UInt")
    initialUser := DllCall("GetGuiResources", "Ptr", process, "UInt", 1, "UInt")
    loop 50 {
        Check(indicator.Show(Mod(A_Index, 3) + 1), "Repeated presentation must succeed")
        indicator.Close()
    }
    Check(DllCall("GetGuiResources", "Ptr", process, "UInt", 0, "UInt") <= initialGdi + 8
        && DllCall("GetGuiResources", "Ptr", process, "UInt", 1, "UInt") <= initialUser + 8,
        "Repeated show/destroy must not accumulate GDI or USER resources")
    FileAppend "PASS: resident GDI+ lifetime, bounded render caches, interruptible preparation, 50 repeated presentations, antialias/DPI, real card/shadow click-through and dismissal`n", logPath, "UTF-8"
}
catch as err {
    FileAppend "FAIL: " err.Message "`nExtra: " err.Extra "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}
finally {
    if IsObject(indicator)
        indicator.Close()
    if IsObject(main)
        main.Destroy()
    DllCall("SetCursorPos", "Int", savedX, "Int", savedY, "Int")
}
ExitApp 0

LayoutTests() {
    for dpi in [96, 144, 192] {
        work := {Left: -1920, Top: -200, Right: 0, Bottom: 840}
        layout := VDIndicatorLayout(work, dpi)
        Check(layout.Width = Round(128 * dpi / 96) && layout.Height = Round(48 * dpi / 96),
            "Size must follow the target monitor's DPI")
        Check(layout.X >= work.Left && layout.X + layout.Width <= work.Right
            && layout.Y >= work.Top && layout.Y + layout.Height <= work.Bottom,
            "Negative monitor origins must remain valid")
        Check(layout.Y + layout.Height = work.Bottom - Round(16 * dpi / 96),
            "Place the card above the work area's bottom edge")
    }
    tiny := VDIndicatorLayout({Left: 10, Top: 20, Right: 90, Bottom: 50}, 192)
    Check(tiny.X = 10 && tiny.Y = 20 && tiny.Width = 80 && tiny.Height = 30,
        "Keep even unusually small work areas within bounds")
}

AntialiasTests() {
    for dpi in [96, 144, 192] {
        layout := VDIndicatorLayout({Left: 0, Top: 0, Right: 1920, Bottom: 1080}, dpi)
        for light in [true, false] {
            image := VDIndicatorCardImage(layout, "桌面 1", light)
            Check(NumGet(image.Pixels, 0, "UInt") = 0, "Outside rounded corners must be fully transparent")
            partial := false
            loop layout.Radius {
                y := A_Index - 1
                loop layout.Radius {
                    x := A_Index - 1
                    alpha := NumGet(image.Pixels, (y * image.Width + x) * 4 + 3, "UChar")
                    if alpha > 0 && alpha < 245
                        partial := true
                }
            }
            Check(partial, "Each theme and DPI must have partially covered corner pixels")
            ink := false
            loop image.Width * image.Height {
                value := NumGet(image.Pixels, (A_Index - 1) * 4, "UInt")
                alpha := value >> 24
                Check((value & 255) <= alpha && ((value >> 8) & 255) <= alpha
                    && ((value >> 16) & 255) <= alpha, "All pixels must use premultiplied alpha without fringes")
                if alpha > 245
                    ink := true
            }
            Check(ink, "Text must be rendered into the card bitmap")
        }
    }
}

RendererLifetimeTests() {
    runtime := VDIndicatorGraphics()
    module := runtime.Module, token := runtime.Token
    layout := VDIndicatorLayout({Left: 0, Top: 0, Right: 1920, Bottom: 1080}, 96)
    card := VDIndicatorCachedCard(layout, "桌面 1", true)
    shadow := VDIndicatorCachedShadow(layout)
    loop 200 {
        Check(VDIndicatorCachedCard(layout, "桌面 1", true).Pixels.Ptr = card.Pixels.Ptr
            && VDIndicatorCachedShadow(layout).Pixels.Ptr = shadow.Pixels.Ptr,
            "Repeated navigation must reuse cached surfaces without pixel loops or font recreation")
        Check(runtime.Token = token && runtime.Module = module
            && DllCall("GetModuleHandleW", "Str", "gdiplus.dll", "Ptr") = module,
            "GDI+ and its module must stay resident between calls")
    }
    Check(runtime.Users = 0, "All temporary GDI+ objects must be released after rendering")
    runtime.Users += 1
    try runtime.Stop()
    finally runtime.Users -= 1
    Check(runtime.Token = token && runtime.Module = module,
        "Shutdown must not invalidate a render interrupted by process exit")
    loop 25
        VDIndicatorCachedCard(layout, "桌面 " (100 + A_Index), true)
    Check(VDIndicatorCachedCard(layout, "桌面 1", true).Pixels.Ptr != card.Pixels.Ptr,
        "Evict old card surfaces so the cache cannot grow without limit")
}

class InterruptibleIndicator extends VDIndicator {
    __New(duration, viewport) {
        super.__New(duration, viewport)
        this.PreparedCritical := -1
        this.Supersede := false
    }
    Prepare(layout, text, light) {
        this.PreparedCritical := A_IsCritical
        if this.Supersede
            this.Begin()
        return super.Prepare(layout, text, light)
    }
}

Check(condition, message) {
    if !condition
        throw Error(message)
}

WaitFor(predicate) {
    started := A_TickCount
    while !predicate.Call() {
        if A_TickCount - started >= 2000
            throw Error("Timed out waiting for indicator dismissal")
        Sleep 20
    }
}
