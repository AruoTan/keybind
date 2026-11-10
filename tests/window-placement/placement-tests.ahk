#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/window-placement/window-placement.ahk
#Include %A_LineFile%/../../../src/modules/remote-desktop/remote-desktop.ahk

logPath := A_Args[1]
try {
    FirstShow()
    ExistingAndSingleScreen()
    OwnerOrdering()
    SkippedWindows()
    FailedAndUnconfirmedMove()
    NavigationAndDisconnect()
    ChangedIdentity()
    RunRequests()
    RectangleTests()
    NativeHandled()
    NativeMaximizedPlacement()
    NativeEvents()
    FileAppend "PASS: placement routing, identity, deadlines, Run reuse, owner ordering, negative coordinates; real cross-process WinEvents and window movement on simulated monitor work areas`n", logPath, "UTF-8"
}
catch as err {
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}
ExitApp 0

Check(condition, message) {
    if !condition
        throw Error(message)
}

class PlacementFixture {
    __New() {
        this.Live := Map(), this.Locations := Map(), this.Owners := Map()
        this.Skip := Map(), this.Runs := Map(), this.Moves := [], this.Logs := []
        this.Ready := true, this.Fail := false, this.IgnoreMove := false, this.Disconnected := false
        this.Controller := PlacementController(this, (message) => this.Logs.Push(message))
    }
    Add(hwnd, owner := 0) {
        token := {Hwnd: hwnd, Pid: 100 + hwnd, Thread: 200 + hwnd}
        this.Live[hwnd] := token, this.Locations[hwnd] := "left", this.Owners[hwnd] := owner
        return token
    }
    Same(left, right) => left.Hwnd = right.Hwnd && left.Pid = right.Pid && left.Thread = right.Thread
    Valid(token) => this.Live.Has(token.Hwnd) && this.Same(this.Live[token.Hwnd], token)
    RunDialog(hwnd) => this.Runs.Has(hwnd)
    WindowMonitor(hwnd) => this.Locations[hwnd]
    Available() => this.Ready
    Inspect(hwnd) => this.Skip.Has(hwnd) ? 0 : {Owner: this.Owners[hwnd]}
    Move(token, target) {
        this.Moves.Push({Hwnd: token.Hwnd, Target: target})
        if this.Fail || this.Disconnected
            throw Error("simulated placement failure")
        if !this.IgnoreMove
            this.Locations[token.Hwnd] := target
    }
    Show(hwnd, target := "right", now := 0) => this.Controller.Event(0x8002, this.Live[hwnd], target, now)
}

FirstShow() {
    f := PlacementFixture(), f.Add(1), f.Show(1)
    f.Show(1, "left", 10)
    f.Controller.Tick(59)
    Check(f.Moves.Length = 0, "Wait briefly for the app's initial geometry")
    f.Controller.Tick(60), f.Controller.Tick(90)
    Check(f.Moves.Length = 1 && f.Locations[1] = "right" && f.Controller.Pending.Count = 0,
        "Keep the monitor captured on first show and confirm the move")
    f.Show(1, "left", 100)
    f.Controller.Event(3, f.Live[1], "left", 100)
    f.Controller.Tick(200)
    Check(f.Moves.Length = 1, "Repeated show/foreground events must not move an existing app")
}

ExistingAndSingleScreen() {
    f := PlacementFixture(), token := f.Add(1)
    f.Controller.Remember(token), f.Show(1), f.Controller.Tick(100)
    Check(f.Moves.Length = 0, "Windows present before startup, including hidden ones, stay put")
    f.Add(2), f.Show(2, ""), f.Show(2, "right", 100), f.Controller.Tick(200)
    Check(f.Moves.Length = 0, "Connecting another monitor must not reclassify old windows as new")
}

OwnerOrdering() {
    f := PlacementFixture(), f.Add(1), f.Add(2, 1)
    f.Show(2, "left"), f.Show(1, "right")
    f.Controller.Tick(60), f.Controller.Tick(90), f.Controller.Tick(120), f.Controller.Tick(150)
    Check(f.Moves.Length = 2 && f.Moves[1].Hwnd = 1
        && f.Locations[1] = "right" && f.Locations[2] = "right",
        "Wait for the owner's placement, then place the dialog on its owner's monitor")
    f.Add(3, 1), f.Show(3, "left", 200), f.Controller.Tick(300)
    Check(f.Locations[3] = "right", "New dialogs follow an existing owner rather than the mouse")
}

SkippedWindows() {
    f := PlacementFixture()
    for hwnd in [1, 2, 3, 4] {
        f.Add(hwnd), f.Skip[hwnd] := true, f.Show(hwnd)
    }
    f.Controller.Tick(100)
    Check(f.Moves.Length = 0 && f.Controller.Pending.Count = 0,
        "Ineligible, minimized, cloaked and full-screen windows must never be moved")
    f.Show(1, "left", 200), f.Controller.Tick(300)
    Check(f.Moves.Length = 0, "A skipped window must not be moved on later activation")
}

FailedAndUnconfirmedMove() {
    f := PlacementFixture(), f.Add(1), f.Show(1), f.Fail := true
    f.Controller.Tick(100), f.Controller.Tick(200)
    Check(f.Moves.Length = 1 && f.Locations[1] = "left" && f.Logs.Length = 1,
        "A failed API call logs once and leaves the window alone")
    f := PlacementFixture(), f.Add(1), f.Show(1), f.IgnoreMove := true
    f.Controller.Tick(100), f.Controller.Tick(500), f.Controller.Tick(1000)
    Check(f.Moves.Length = 1 && f.Controller.Pending.Count = 0
        && InStr(f.Logs[1], "not confirmed"), "Do not fight an application that rejects placement")
}

NavigationAndDisconnect() {
    f := PlacementFixture(), f.Add(1), f.Show(1), f.Ready := false
    f.Controller.Tick(100)
    Check(f.Moves.Length = 0, "Placement must not overlap a virtual desktop operation")
    f.Ready := true, f.Controller.Tick(200)
    Check(f.Moves.Length = 1, "Resume placement when desktop navigation releases its guard")
    f := PlacementFixture(), f.Add(1), f.Show(1), f.Ready := false
    f.Controller.Tick(1100), f.Ready := true, f.Controller.Tick(1200)
    Check(f.Moves.Length = 0 && f.Controller.Pending.Count = 0, "A busy desktop must not defer a move indefinitely")
    f := PlacementFixture(), f.Add(1), f.Show(1), f.Disconnected := true
    f.Controller.Tick(100)
    Check(f.Locations[1] = "left" && f.Controller.Pending.Count = 0,
        "A disconnected target leaves the app on its original monitor")
}

ChangedIdentity() {
    f := PlacementFixture(), old := f.Add(1), f.Show(1)
    f.Live[1] := {Hwnd: 1, Pid: 900, Thread: 901}
    f.Controller.Tick(100)
    Check(f.Moves.Length = 0, "Never apply a pending placement to a reused HWND")
    f.Show(1, "right", 200), f.Controller.Tick(300)
    Check(f.Moves.Length = 1, "A new window identity may be placed even when its handle is reused")
    f.Controller.Event(0x8001, {Hwnd: 1}, "", 400)
    Check(!f.Controller.Known.Has(1) && !f.Controller.Pending.Has(1), "Destroy events release tracking")
}

RunRequests() {
    f := PlacementFixture(), token := f.Add(1), f.Runs[1] := true
    f.Controller.Remember(token), f.Controller.Event(3, token, "right", 0)
    f.Controller.Tick(100)
    Check(f.Moves.Length = 0, "Alt-Tab to an existing Run dialog must not relocate it")
    f.Controller.RequestRun("right", 200)
    f.Controller.Event(3, token, "left", 210), f.Controller.Tick(300), f.Controller.Tick(350)
    Check(f.Locations[1] = "right" && f.Moves.Length = 1,
        "An explicit Win+R invocation routes a reused dialog to the keypress monitor")
    f.Controller.Event(3, token, "left", 400), f.Controller.Tick(500)
    Check(f.Moves.Length = 1, "Run monitor requests are consumed once")
    f.Controller.RequestRun("left", 600)
    f.Controller.Event(3, token, "left", 1700), f.Controller.Tick(1800)
    Check(f.Moves.Length = 1, "An expired Win+R request must not affect unrelated activation")
}

RectangleTests() {
    source := {Left: -1920, Top: -1080, Right: 0, Bottom: 0}
    target := {Left: 0, Top: 40, Right: 1280, Bottom: 1024}
    rect := PlacementRectangle({X: -1800, Y: -1000, Width: 800, Height: 600}, source, target)
    Check(rect.X = 120 && rect.Y = 120, "Translate negative monitor origins and taskbar offsets")
    rect := PlacementRectangle({X: -100, Y: -50, Width: 800, Height: 600}, source, target)
    Check(rect.X = 480 && rect.Y = 424, "Keep a window's top-left within the target work area")
    rect := PlacementRectangle({X: -1900, Y: -1060, Width: 2000, Height: 1500}, source, target)
    Check(rect.X = 0 && rect.Y = 40 && rect.Width = 2000 && rect.Height = 1500,
        "Do not resize fixed-size or oversized windows merely to fit the target")
}

NativeHandled() {
    app := Gui(, "Native placement decision fixture")
    try {
        app.Show("x80 y80 w260 h150")
        Check(DllCall("SetPropW", "Ptr", app.Hwnd, "Str", "Keybind.Placement.Done.v1", "Ptr", 1, "Int"),
            "Mark the native first-show decision")
        Check(!PlacementTestNative().Inspect(app.Hwnd), "After-show fallback must not override a native decision")
    }
    finally app.Destroy()
}

class PlacementTestMonitors {
    Count() => 2
    Pointer() => "right"
    Work(device) => device = "left" ? {Left: 0, Top: 0, Right: 640, Bottom: 720}
        : {Left: 640, Top: 0, Right: 1280, Bottom: 720}
    Window(hwnd) {
        WinGetPos &x, &y, &width, &height, "ahk_id " hwnd
        return x + width // 2 < 640 ? "left" : "right"
    }
}

class PlacementTestNative extends PlacementNative {
    __New() {
        super.__New()
        this.Monitors := PlacementTestMonitors()
        if A_Args.Length > 1 && A_Args[2] = "--skip-dwm"
            this.Windows := PlacementWineWindows()
    }
    Bounds(device) => this.Monitors.Work(device)
}

class PlacementWineWindows extends VDWindows {
    Cloak(hwnd) => 0 ; Wine does not implement Windows' desktop cloaking.
}

class PlacementMaxMonitors extends PlacementTestMonitors {
    Window(hwnd) => "left"
}

NativeMaximizedPlacement() {
    app := Gui(, "Maximized placement fixture"), other := Gui(, "Focus preservation fixture")
    try {
        app.Show("x80 y80 w260 h150")
        WinMaximize "ahk_id " app.Hwnd
        other.Show("x200 y200 w200 h100")
        WinActivate "ahk_id " other.Hwnd
        WinWaitActive "ahk_id " other.Hwnd, , 1
        before := Buffer(44, 0), after := Buffer(44, 0)
        NumPut "UInt", 44, before
        NumPut "UInt", 44, after
        Check(DllCall("GetWindowPlacement", "Ptr", app.Hwnd, "Ptr", before, "Int"), "Read normal restore bounds")
        api := PlacementTestNative(), api.Monitors := PlacementMaxMonitors()
        api.Move(api.Windows.Token(app.Hwnd), "right")
        Sleep 80
        Check(DllCall("IsZoomed", "Ptr", app.Hwnd, "Int"), "Relocating a maximized app preserves maximization")
        Check(DllCall("GetWindowPlacement", "Ptr", app.Hwnd, "Ptr", after, "Int")
            && NumGet(after, 28, "Int") >= 640, "Translate the normal restore bounds to the destination work area")
        Check(DllCall("GetForegroundWindow", "Ptr") = other.Hwnd, "Moving a maximized background window must not steal focus")
    }
    finally app.Destroy(), other.Destroy()
}

NativeEvents() {
    watcher := 0, pid := 0
    try {
        api := PlacementTestNative(), watcher := PlacementWatcher(api, () => true)
        watcher.Start()
        Check(watcher.Hooks.Length = 2 && watcher.Callback, "Register real out-of-context event hooks")
        Run '"' A_AhkPath '" /ErrorStdOut=UTF-8 "' A_ScriptDir '\window-fixture.ahk"', , , &pid
        root := WinWait("Placement child primary ahk_pid " pid, , 3)
        dialog := WinWait("Placement child dialog ahk_pid " pid, , 3)
        Check(root && dialog, "Start a real application with an owned dialog")
        deadline := A_TickCount + 2500
        while A_TickCount < deadline && (api.WindowMonitor(root) != "right"
            || api.WindowMonitor(dialog) != "right")
            Sleep 20
        Check(api.WindowMonitor(root) = "right" && api.WindowMonitor(dialog) = "right",
            "Real cross-process SHOW events must move the app and dialog to the selected work area")
        Check(api.Inspect(dialog).Owner = root, "Resolve the actual visible owner")
        Check(!api.Inspect(DllCall("GetDesktopWindow", "Ptr")), "Never move the desktop")
        WinMove 100, 100, , , "ahk_id " root
        WinHide "ahk_id " root
        WinShow "ahk_id " root
        Sleep 250
        Check(api.WindowMonitor(root) = "left", "A later SHOW of an existing app must stay where the user put it")
        WinMinimize "ahk_id " root
        Check(!api.Inspect(root), "A real minimized window must not be moved or restored")
        watcher.Close(), watcher.Close()
        Check(watcher.Callback = 0 && watcher.Hooks.Length = 0, "Release timers/hooks/callbacks idempotently")
    }
    finally {
        if IsObject(watcher)
            watcher.Close()
        if pid && ProcessExist(pid)
            ProcessClose pid
    }
}
