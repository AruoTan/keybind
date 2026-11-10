#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/window-placement/window-placement.ahk
#Include %A_LineFile%/../../../src/modules/remote-desktop/remote-desktop.ahk
#Include %A_LineFile%/../../../src/modules/keyboard.ahk

logPath := A_Args[1], hook := 0, callback := 0, presses := [], requests := []
try {
    callback := CallbackCreate(ObserveKeys, , 3)
    hook := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", callback,
        "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
    Check(hook, "Observe and swallow the real replay without opening a system dialog")
    Replay(0, "Run works before placement initialization")
    WindowPlacementMonitors := RunMonitorsFixture()
    Replay(0, "Missing native bridge must not disable Run")
    WindowPlacementNative := RunBridgeFixture()
    WindowPlacementMonitors.Screens := 1
    Replay(0, "Single-screen Run needs no native request")
    WindowPlacementMonitors.Screens := 2
    Replay(1, "Publish the selected monitor before replaying Win+R")
    Check(requests[1] = "right", "Use the pointer monitor")
    WindowPlacementNative.Accept := false
    Replay(1, "Rejected placement still invokes the system Run dialog")
    WindowPlacementNative.Fail := true
    Replay(1, "A native request exception must not swallow Win+R")
    WindowPlacementMonitors.Fail := true
    Replay(0, "A monitor discovery exception must not swallow Win+R")
    WindowPlacementStop(), WindowPlacementStop()
    FileAppend "PASS: real Win+R replay exactly once after native publication, single-screen/missing/rejected/failed placement, discovery errors, and idempotent shutdown; system Run UI and physical RDP keyboard behavior unverified`n", logPath, "UTF-8"
}
catch as err {
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}
finally {
    if hook
        DllCall "UnhookWindowsHookEx", "Ptr", hook
    if callback
        CallbackFree callback
}
ExitApp 0

Check(condition, message) {
    if !condition
        throw Error(message)
}

Replay(expected, message) {
    global presses, requests
    presses := [], requests := []
    WindowPlacementRun()
    Sleep 30
    Check(presses.Length = 1 && presses[1] = expected && requests.Length = expected, message)
}

ObserveKeys(code, message, data) {
    global presses, requests
    if code >= 0 {
        key := NumGet(data, "UInt")
        if key = 0x52 || key = 0x5B || key = 0x5C {
            if key = 0x52 && !(NumGet(data, 8, "UInt") & 0x80)
                presses.Push(requests.Length)
            return 1
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "Ptr", message, "Ptr", data, "Ptr")
}

class RunMonitorsFixture {
    Screens := 2, Fail := false
    Count() {
        if this.Fail
            throw Error("Monitor fixture failure")
        return this.Screens
    }
    Pointer() => "right"
}

class RunBridgeFixture {
    Accept := true, Fail := false
    RequestRun(device) {
        global requests
        requests.Push(device)
        if this.Fail
            throw Error("Native request fixture failure")
        return this.Accept
    }
    Close() => 0
}
