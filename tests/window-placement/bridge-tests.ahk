#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/window-placement/window-placement.ahk
#Include %A_LineFile%/../../../src/modules/remote-desktop/remote-desktop.ahk

logPath := A_Args[1], bridge := PlacementBridge(() => true), failure := ""
try {
    bridge.Start(A_Args[2])
    bridge.Start(A_Args[2])
    deadline := A_TickCount + 3000
    while !bridge.HostReported && A_TickCount < deadline
        Sleep 20
    Check(bridge.Host && ProcessExist(bridge.Host) && bridge.HostReported, "AHK starts and observes native x86 host")
    Check(DllCall(bridge.Functions["Status"], "UInt", 0, "UInt") = bridge.Host, "Observe actual x86 hook readiness")
    Check(bridge.RequestRun(VDMonitors().Pointer()), "Publish Run target through the AHK bridge")
    Check(!bridge.RequestRun("MISSING"), "Reject an unknown Run target")
    gateCalls := [], allowed := false
    state := {Controller: {Busy: false}, PlacementGate: (block) => (gateCalls.Push(block), !block || allowed)}
    Check(!VDNavigationBegin(state) && !state.HasOwnProp("Navigating"), "Reject navigation while a native show is in flight")
    allowed := true
    state.PlacementGate := ObjBindMethod(bridge, "Block")
    Check(VDNavigationBegin(state) && state.Navigating, "Navigation acquires the native gate")
    Check(!VDNavigationBegin(state), "Repeated navigation does not reacquire an owned gate")
    state.Navigating := false, state.PlacementGate.Call(false)
    bridge.Update()
    host := bridge.Host
    bridge.Close(), bridge.Close()
    bridge.Start(A_Args[2])
    ProcessWaitClose host, 3
    Check(!ProcessExist(host) && ProcessExist(bridge.Host), "Old x86 host exits after rapid restart in the same controller process")
    host := bridge.Host
    bridge.Close()
    ProcessWaitClose host, 3
    Check(!ProcessExist(host) && !bridge.Module, "AHK shutdown releases both architectures idempotently")
    FileAppend "PASS: AHK native DLL/exports, x86 readiness, virtual-desktop guard, heartbeat, rapid restart and idempotent shutdown`n", logPath, "UTF-8"
}
catch as err {
    failure := err.Message "`n" err.Stack
}
finally bridge.Close()
if failure != "" {
    FileAppend "FAIL: " failure "`n", logPath, "UTF-8"
    ExitApp 1
}
ExitApp 0

Check(condition, message) {
    if !condition
        throw Error(message)
}
