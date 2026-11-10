; Route first-show application windows without intercepting keyboard input.
#Include %A_LineFile%/../native.ahk
#Include %A_LineFile%/../bridge.ahk

WindowPlacementInit() {
    global WindowPlacementState, WindowPlacementNative, VirtualDesktopState
    try {
        WindowPlacementNative := PlacementBridge(() => !RemoteDesktopActive())
        try {
            WindowPlacementNative.Start()
            if IsSet(VirtualDesktopState) && IsObject(VirtualDesktopState)
                VirtualDesktopState.PlacementGate := ObjBindMethod(WindowPlacementNative, "Block")
        }
        catch as err {
            WindowPlacementNative.Close()
            PlacementLog("Pre-show unavailable; using after-show fallback: " err.Message)
        }
        WindowPlacementState := PlacementWatcher(PlacementNative(), () => !RemoteDesktopActive())
        WindowPlacementState.Start()
        OnExit WindowPlacementStop
        PlacementLog("Ready; PID=" DllCall("GetCurrentProcessId", "UInt")
            "; new application windows + Run; Start/Search belong to explorer extension")
    }
    catch as err {
        WindowPlacementStop()
        PlacementLog("Disabled: " err.Message)
    }
}

WindowPlacementStop(*) {
    global WindowPlacementState, WindowPlacementNative
    if IsSet(WindowPlacementNative) && IsObject(WindowPlacementNative)
        WindowPlacementNative.Close()
    if IsSet(WindowPlacementState) && IsObject(WindowPlacementState)
        WindowPlacementState.Close()
}

WindowPlacementRun(*) {
    global WindowPlacementState
    if !IsSet(WindowPlacementState) || !IsObject(WindowPlacementState)
        return
    try {
        api := WindowPlacementState.Api
        if api.Monitors.Count() > 1
            WindowPlacementState.Controller.RequestRun(api.Monitors.Pointer(), A_TickCount)
    }
    catch as err
        PlacementLog("Run monitor selection failed: " err.Message)
}

class PlacementController {
    __New(api, log := PlacementLog) {
        this.Api := api, this.Log := log
        this.Known := Map(), this.Pending := Map()
        this.RunTarget := "", this.RunDeadline := 0
    }

    Remember(token) => this.Known[token.Hwnd] := token
    RequestRun(target, now) => (this.RunTarget := target, this.RunDeadline := now + 1000)

    Event(event, token, target, now) {
        hwnd := token.Hwnd
        if event = 0x8001 { ; EVENT_OBJECT_DESTROY
            if this.Known.Has(hwnd)
                this.Known.Delete(hwnd)
            if this.Pending.Has(hwnd)
                this.Pending.Delete(hwnd)
            return
        }
        if !this.Api.Valid(token)
            return
        known := this.Known.Has(hwnd) && this.Api.Same(this.Known[hwnd], token)
        ; Run reuses its dialog on some builds. Other existing windows stay put.
        run := this.Api.RunDialog(hwnd)
        requested := run && this.RunTarget != "" && now <= this.RunDeadline
        if (known && !requested) || (event = 3 && !requested) || this.Pending.Has(hwnd)
            return
        if requested
            target := this.RunTarget, this.RunTarget := ""
        this.Remember(token)
        if target = ""
            return ; Still remember windows opened while only one screen is connected.
        this.Pending[hwnd] := {Token: token, Target: target, Due: now + 60,
            Deadline: now + 1000, Checking: false, Run: run}
    }

    Tick(now) {
        for hwnd, request in this.Pending.Clone() {
            if !this.Api.Valid(request.Token) {
                this.Pending.Delete(hwnd)
                continue
            }
            if now < request.Due
                continue
            try {
                if request.Checking {
                    if this.Api.WindowMonitor(hwnd) = request.Target {
                        this.Pending.Delete(hwnd)
                        this.Log.Call("Placed; hwnd=" Format("0x{:X}", hwnd) "; monitor=" request.Target
                            "; kind=" (request.Run ? "run" : "application"))
                    } else if now >= request.Deadline {
                        this.Pending.Delete(hwnd)
                        this.Log.Call("Placement not confirmed; hwnd=" Format("0x{:X}", hwnd)
                            "; monitor=" request.Target)
                    }
                    continue
                }
                if !this.Api.Available() {
                    if now >= request.Deadline {
                        this.Pending.Delete(hwnd)
                        this.Log.Call("Placement expired; desktop navigation busy; hwnd=" Format("0x{:X}", hwnd))
                    }
                    continue
                }
                if now >= request.Deadline {
                    this.Pending.Delete(hwnd)
                    this.Log.Call("Placement expired; hwnd=" Format("0x{:X}", hwnd))
                    continue
                }
                info := this.Api.Inspect(hwnd)
                if !IsObject(info) {
                    this.Pending.Delete(hwnd)
                    continue
                }
                ; Owned dialogs follow the real visible owner, not a hidden framework proxy.
                if info.Owner {
                    if this.Pending.Has(info.Owner)
                        continue
                    request.Target := this.Api.WindowMonitor(info.Owner)
                }
                if this.Api.WindowMonitor(hwnd) = request.Target {
                    this.Pending.Delete(hwnd)
                    continue
                }
                this.Api.Move(request.Token, request.Target)
                request.Checking := true
            }
            catch as err {
                this.Pending.Delete(hwnd)
                this.Log.Call("Placement failed; hwnd=" Format("0x{:X}", hwnd) "; " err.Message)
            }
        }
    }
}

class PlacementWatcher {
    __New(api, allowed) {
        this.Api := api, this.Allowed := allowed
        this.Controller := PlacementController(api)
        this.Events := [], this.Hooks := [], this.Callback := 0, this.Busy := false, this.Closed := false
        this.Timer := ObjBindMethod(this, "Drain")
    }

    Start() {
        ; Hidden pre-existing HWNDs are not newly opened applications.
        for hwnd in this.Api.Windows.All() {
            try this.Controller.Remember(this.Api.Windows.Token(hwnd))
        }
        this.Callback := CallbackCreate(ObjBindMethod(this, "Event"), , 7)
        try {
            for range in [[0x8001, 0x8002], [3, 3]] {
                hook := DllCall("SetWinEventHook", "UInt", range[1], "UInt", range[2],
                    "Ptr", 0, "Ptr", this.Callback, "UInt", 0, "UInt", 0, "UInt", 2, "Ptr")
                if !hook
                    throw OSError(, , "Cannot watch window creation")
                this.Hooks.Push(hook)
            }
            SetTimer this.Timer, 30
        }
        catch as err {
            this.Close()
            throw err
        }
    }

    Event(hook, event, hwnd, object, child, thread, time) {
        if this.Closed || !hwnd || object != 0 || child != 0
            return
        try {
            if event = 0x8001 {
                this.Events.Push({Event: event, Token: {Hwnd: hwnd}, Target: "", Time: A_TickCount})
                return
            }
            if DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd
                return
            token := this.Api.Windows.Token(hwnd)
            target := this.Allowed.Call() && this.Api.Monitors.Count() > 1
                ? this.Api.Monitors.Pointer() : ""
            this.Events.Push({Event: event, Token: token, Target: target, Time: A_TickCount})
        }
        catch {
            ; Closing HWNDs cannot be queried reliably; never throw through a native callback.
        }
    }

    Drain() {
        if this.Busy
            return
        this.Busy := true
        try {
            wasCritical := A_IsCritical
            Critical "On"
            events := this.Events, this.Events := []
            Critical wasCritical
            for item in events {
                try this.Controller.Event(item.Event, item.Token, item.Target, item.Time)
                catch as err
                    PlacementLog("Window event failed: " err.Message)
            }
            this.Controller.Tick(A_TickCount)
        }
        finally this.Busy := false
    }

    Close() {
        this.Closed := true
        SetTimer this.Timer, 0
        retained := []
        for hook in this.Hooks {
            if !DllCall("UnhookWinEvent", "Ptr", hook, "Int") {
                retained.Push(hook)
                PlacementLog("UnhookWinEvent failed; callback retained; error=" A_LastError)
            }
        }
        this.Hooks := retained
        if this.Callback && !retained.Length
            CallbackFree(this.Callback), this.Callback := 0
        this.Events := []
        this.Controller.Pending.Clear()
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
