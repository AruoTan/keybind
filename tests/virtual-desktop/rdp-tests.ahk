#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk
#Include %A_LineFile%/../../../src/modules/remote-desktop/remote-desktop.ahk

logPath := A_Args[1]
fixturePid := 0, fixtureDir := ""
try {
    installs := [], guard := RDPHookGuard(() => installs.Push(true))
    guard.Update("", 100, false)
    Check(installs.Length = 0, "No RDP session must leave the hook alone")
    guard.Update("session-a", 200, true)
    Check(installs.Length = 0, "Do not reinstall during a held chord")
    guard.Update("session-a", 300, false)
    Check(installs.Length = 1, "Reinstall after the chord is released")
    guard.Update("session-a", 799, false)
    Check(installs.Length = 1, "Wait before the delayed reinstall")
    guard.Update("session-a", 800, true)
    Check(installs.Length = 1, "Delayed reinstall must also wait for key-up")
    guard.Update("session-a", 900, false)
    guard.Update("session-a", 2000, false)
    Check(installs.Length = 3, "Stable fullscreen sessions must periodically reclaim hook priority")
    guard.Update("session-a-fullscreen", 2100, false)
    Check(installs.Length = 4, "Fullscreen transition must refresh priority")
    guard.Update("", 2200, false)
    guard.Update("", 4000, false)
    Check(installs.Length = 4, "Leaving RDP must cancel pending refresh")
    guard.Update("session-b", 4100, false)
    Check(installs.Length = 5, "Entering another RDP session must refresh")
    guard.Update("session-c", 4200, true)
    guard.Update("", 4300, false)
    Check(installs.Length = 5, "Cancelled activation must not refresh later")

    PhysicalChordTests()
    StaleStateTests()
    StuckCtrlBlocksShift()
    ModifierTraceTests()
    ContinuousNavigationTests()

    Check(!RemoteDesktopActive() && RemoteDesktopSignature() = "", "Non-RDP foreground must not match")
    RemoteDesktopKeysDown() ; Exercise the actual Win32 call and AHK types.
    Check(RemoteDesktopInit(), "Physical hook and timer must initialize without an RDP session")
    RemoteDesktopRefresh()
    SetTimer RemoteDesktopRefresh, 0
    RDPReinstallHook() ; Execute the real AHK hook refresh, not just a fake.

    fixtureDir := A_Temp "\keybind-rdp-test-" DllCall("GetCurrentProcessId", "UInt")
    DirCreate fixtureDir
    FileCopy A_AhkPath, fixtureDir "\msrdc.exe", true
    Run '"' fixtureDir '\msrdc.exe" /ErrorStdOut=UTF-8 "' A_ScriptDir '\rdp-fixture.ahk"', , , &fixturePid
    fixtureHwnd := WinWait("Keybind RDP recognition fixture ahk_pid " fixturePid, , 5)
    Check(fixtureHwnd, "Windows App process fixture must start")
    WinActivate "ahk_id " fixtureHwnd
    Check(WinWaitActive("ahk_id " fixtureHwnd, , 5), "Windows App fixture must become foreground")
    Check(RemoteDesktopActive() = fixtureHwnd, "msrdc session must match without mstsc's window class")
    Check(InStr(RemoteDesktopSignature(), "msrdc.exe:"), "Signature must identify Windows App process")
    RemoteDesktopRefresh()
    Check(RemoteDesktopGuard.Signature != "", "Actual foreground recognition must arm the hook guard")
    NativeHookTests(fixtureHwnd)
    FocusHandoffTests(fixtureHwnd)
    RememberedFocusTests(fixtureHwnd)
    RemoteDesktopStop()
    ProcessClose fixturePid
    fixturePid := 0
    DirDelete fixtureDir, true
    fixtureDir := ""
    FileAppend "PASS: continuous Ctrl+Win navigation, remembered desktop focus, physical RDP chords, callback ABI and focus handoff/typing without a click`n", logPath, "UTF-8"
    ExitApp 0
}
catch as err {
    RemoteDesktopStop()
    if fixturePid && ProcessExist(fixturePid)
        ProcessClose fixturePid
    if fixtureDir != "" && DirExist(fixtureDir)
        DirDelete fixtureDir, true
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}

Check(condition, message) {
    if !condition
        throw Error(message, -1)
}

ContinuousNavigationTests() {
    hook := RDPKeyboardHook()
    try {
        filter := hook.Filter
        filter.Event(0x5B, false, false, true, true)
        filter.Event(0xA2, false, false, true, true)
        Check(filter.Event(0x27, false, false, true, true) = 2, "Initial RDP switch must be local")
        Check(filter.Event(0x27, true, false, false, true) = -1, "Release first arrow after leaving RDP")
        hook.ObserveWindow(0, 0, true)
        hook.ObserveWindow(0, 5000, true)
        Check(filter.SwitchChain && filter.Any(0x5B) && filter.Any(0xA2),
            "Background cleanup must preserve a continuing physical navigation chord")
        Check(filter.Event(0x27, false, false, false, true) = 2,
            "Held Ctrl+Win must switch again on an ordinary local desktop")
        Check(filter.Event(0x27, false, false, false, true) = -1,
            "Holding the arrow must still execute only once")
        filter.Event(0x27, true, false, false, true)
        Check(filter.Event(0x25, false, false, false, true) = 1,
            "Opposite arrow must return toward the remembered RDP desktop")
        filter.Event(0x25, true, false, false, true)
        filter.Event(0xA2, true, false, false, true)
        Check(!filter.SwitchChain, "Physical Ctrl release ends continuation")
        filter.Event(0x5B, true, false, false, true)
        Check(filter.Event(0x27, false, false, false, true) = 0,
            "A plain arrow after release must pass through")
        filter.Event(0x27, true, false, false, true)
        filter.Event(0x5B, false, false, false, true)
        filter.Event(0xA0, false, false, false, true)
        Check(filter.Event(0x27, false, false, false, true) = 0,
            "Local Win+Shift must remain with its original window-move hotkey")
    }
    finally hook.Close()
}

PhysicalChordTests() {
    for winKey in [0x5B, 0x5C] {
        for modifier in [0xA0, 0xA1, 0xA2, 0xA3] {
            for arrow in [0x25, 0x27] {
                filter := RDPKeyFilter()
                Check(filter.Event(winKey, false, false, true) = 0, "Win modifier passes through")
                Check(filter.Event(modifier, false, false, true) = 0, "Second modifier passes through")
                expected := (modifier < 0xA2 ? 3 : 1) + (arrow = 0x27)
                Check(filter.Event(arrow, false, false, true) = expected, "Physical left/right chord must match")
                Check(filter.Event(arrow, false, false, true) = -1, "Held-key repeat must be swallowed")
                filter.Event(modifier, true, false, true)
                Check(filter.Event(arrow, false, false, true) = -1, "Changing modifiers must not leak a repeat")
                Check(filter.Event(arrow, true, false, false) = -1, "Owned key-up is swallowed after focus changes")
                Check(filter.Event(arrow, true, false, false) = 0, "Unknown key-up passes without error")
                filter.Event(winKey, true, false, false)
                Check(filter.Down.Count = 0 && filter.Owned.Count = 0, "All physical state must clear")
            }
        }
    }
    filter := RDPKeyFilter()
    filter.Event(0x5B, false, false, true)
    filter.Event(0xA2, false, false, true)
    Check(filter.Event(0x25, false, true, true) = 0 && !filter.Down.Has(0x25), "Injected arrows must not trigger")
    Check(filter.Event(0x45, false, false, true) = 0, "Other Win combinations must pass through")
    Check(filter.Event(0x25, false, false, false) = 0, "Other foreground apps must pass through")
    Check(filter.Event(0x25, false, false, true) = 0, "An arrow already held on entry must not trigger")
    filter.Event(0x25, true, false, true)
    filter.Event(0xA0, false, false, true)
    Check(filter.Event(0x25, false, false, true) = 0, "Ctrl+Shift+Win must not match")
    filter.Event(0x25, true, false, true)
    filter.Event(0xA0, true, false, true)
    filter.Event(0xA4, false, false, true)
    Check(filter.Event(0x25, false, false, true) = 0, "Alt+Ctrl+Win must not match")
    ; An inactive RDP client must not disable the LOCAL desktop keyboard,
    ; even if the old Win/Ctrl state is still recorded after a switch.
    loop 247 {
        vk := A_Index + 7
        Check(filter.Event(vk, false, false, false) = 0,
            "Every unowned key on the local desktop must pass through")
        filter.Event(vk, true, false, false)
    }
}

class FocusFixtureApi {
    __New(origin, destination := 0) {
        this.Origin := origin, this.Destination := destination
        this.Desktop := "source"
        this.SourcePinned := false, this.SourceLocation := "source", this.FailSourceQuery := false
    }
    Current() => this.Desktop
    WindowId(hwnd, *) {
        if hwnd = this.Origin && this.FailSourceQuery
            throw Error("Injected hidden-source query failure")
        return hwnd = this.Origin ? this.SourceLocation : (hwnd = this.Destination ? "target" : "")
    }
    Pinned(hwnd) => hwnd = this.Origin && this.SourcePinned
}

class EmptyDesktopFocus extends RDPSwitchFocus {
    __New(origin, fallback) {
        super.__New(origin)
        this.Fallback := fallback
    }
    ShellWindows() => [this.Fallback]
}

FocusHandoffTests(origin) {
    destination := Gui(, "Keybind local input fixture")
    edit := destination.AddEdit("w160")
    destination.Show("NoActivate w200 h80")
    fallback := Gui("+ToolWindow", "Keybind empty desktop input fixture")
    fallback.Show("NoActivate w120 h60")
    focus := 0
    try {
        api := FocusFixtureApi(origin, destination.Hwnd)
        focus := RDPSwitchFocus(origin)
        Check(focus.Activate(origin), "RDP fixture must have initial foreground focus")
        focus.Before(api, "source", "target")
        Check(DllCall("GetForegroundWindow", "Ptr") = focus.Broker.Hwnd,
            "Real local broker must deactivate the RDP fixture before switching")
        Check(!VDWindows().Ordinary(focus.Broker.Hwnd), "Broker must never count as an application")
        api.Desktop := "target"
        Check(focus.After(api, "source", "target"), "Target app must receive foreground without a click")
        Check(DllCall("GetForegroundWindow", "Ptr") = destination.Hwnd,
            "RDP fixture must not retain focus on the new desktop")
        Check(!InStr(focus.Describe(), "input-focus=0"), "Target edit must have keyboard focus")
        WinHide "ahk_id " origin
        Check(focus.SourceOccupied(api, "source"),
            "A deactivated hidden RDP client must continue occupying its original desktop")
        api.SourcePinned := true
        Check(!focus.SourceOccupied(api, "source"), "Pinned source windows must not block cleanup")
        api.SourcePinned := false, api.SourceLocation := "target"
        Check(!focus.SourceOccupied(api, "source"), "A moved source window must not retain its old desktop")
        api.SourceLocation := "source", api.FailSourceQuery := true, rejected := false
        try focus.SourceOccupied(api, "source")
        catch
            rejected := true
        Check(rejected, "Unknown live source ownership must not authorize cleanup")
        api.FailSourceQuery := false
        DllCall("ShowWindow", "Ptr", origin, "Int", 8, "Int") ; SW_SHOWNA, preserve target focus.
        focus.Close()
        Check(DllCall("GetForegroundWindow", "Ptr") = destination.Hwnd,
            "Destroying the broker must not restore hidden RDP focus")
        ; Verify the input owner receives subsequent ordinary typing, not just
        ; that a foreground HWND changed. This does not exercise a real RDP hook.
        SendEvent "{F24}"
        SendText "local-input-ok"
        Sleep 100
        Check(edit.Value = "local-input-ok", "Typing must work after handoff with no mouse activation")

        api := FocusFixtureApi(origin)
        focus := EmptyDesktopFocus(origin, fallback.Hwnd)
        Check(focus.Activate(origin), "Restore fixture foreground for empty desktop case")
        focus.Before(api, "source", "target")
        api.Desktop := "target"
        Check(focus.After(api, "source", "target"), "Empty desktop must activate a local fallback")
        Check(DllCall("GetForegroundWindow", "Ptr") = fallback.Hwnd,
            "Empty desktop fallback must receive foreground without a click")
        focus.Close()

        focus := RDPSwitchFocus(origin)
        focus.Activate(origin)
        focus.Before(api, "source", "target")
        focus.Close()
        Check(DllCall("GetForegroundWindow", "Ptr") = origin,
            "Failed switch must restore the original foreground and remove the broker")
    }
    finally {
        if IsObject(focus)
            focus.Close()
        destination.Destroy()
        fallback.Destroy()
    }
}

RememberedFocusTests(origin) {
    localApp := Gui(, "Keybind return navigation fixture")
    localApp.AddEdit("w160")
    localApp.Show("NoActivate w200 h80")
    history := RDPFocusHistory(), windows := VDWindows(), focus := 0, localDestroyed := false
    try {
        api := FocusFixtureApi(origin, localApp.Hwnd)
        history.Remember(api, windows, "source", origin)
        remembered := history.Get(api, windows, "source")
        Check(IsObject(remembered) && remembered.Rdp, "Remember the original RDP session identity")
        ; Simulate a user native-switching back with the shell/local window
        ; still in foreground. The remembered RDP must win over that fallback.
        focus := RDPSwitchFocus(localApp.Hwnd, windows, history)
        focus.Activate(localApp.Hwnd)
        api.Desktop := "target"
        focus.Before(api, "target", "source")
        api.Desktop := "source"
        Check(focus.After(api, "target", "source"), "Return must activate the remembered RDP session")
        Check(DllCall("GetForegroundWindow", "Ptr") = origin,
            "Return to RDP must not require a mouse click")
        focus.Close()

        ; Identity remains the same even if deactivation hid the RDP fixture.
        WinHide "ahk_id " origin
        focus := RDPSwitchFocus(localApp.Hwnd, windows, history)
        focus.Activate(localApp.Hwnd)
        api.Desktop := "target"
        focus.Before(api, "target", "source")
        api.Desktop := "source"
        Check(focus.After(api, "target", "source"), "A remembered hidden RDP window must be shown on return")
        Check(DllCall("GetForegroundWindow", "Ptr") = origin, "Hidden RDP must regain foreground")
        focus.Close()

        style := WinGetStyle("ahk_id " origin) & 0x80C00000
        WinMinimize "ahk_id " origin
        focus := RDPSwitchFocus(localApp.Hwnd, windows, history)
        focus.Activate(localApp.Hwnd)
        api.Desktop := "target"
        focus.Before(api, "target", "source")
        api.Desktop := "source"
        Check(focus.After(api, "target", "source"), "Remembered minimized RDP must restore on return")
        Check(!DllCall("IsIconic", "Ptr", origin, "Int")
            && (WinGetStyle("ahk_id " origin) & 0x80C00000) = style,
            "Restoring remembered RDP must preserve its popup/caption mode")
        focus.Close()

        history.Windows["source"] := {Token: {Hwnd: origin, Pid: 0, Thread: 0}, Rdp: true}
        Check(!IsObject(history.Get(api, windows, "source")), "Reused/stale HWND identities must be discarded")
        history.Remember(api, windows, "target", localApp.Hwnd)
        localApp.Destroy()
        localDestroyed := true
        Check(!IsObject(history.Get(api, windows, "target")), "Closed remembered apps must not be activated")
    }
    finally {
        if IsObject(focus)
            focus.Close()
        if !localDestroyed
            localApp.Destroy()
    }
}

NativeHookTests(hwnd) {
    ; Call the actual x64 callback pointer with KBDLLHOOKSTRUCT data, and
    ; exercise the return value that stops the rest of the Windows hook chain.
    hook := RDPKeyboardHook()
    hook.Window := hwnd
    try {
        packet := Buffer(24, 0)
        hook.Filter.Event(0x5B, false, false, true)
        hook.Filter.Event(0xA2, false, false, true)
        NumPut "UInt", 0x27, packet
        Check(DllCall(hook.Address, "Int", 0, "UPtr", 0x100, "Ptr", packet, "Ptr") = 1,
            "Native callback must stop selected arrow key-down")
        Check(hook.Requests.Count = 1, "Native callback must queue exactly one asynchronous action")
        Check(InStr(hook.Probe, "W=1; C=1; S=0; A=0") && InStr(hook.Probe, "action=2"),
            "Arrow diagnostics must record only modifier bits and classification")
        hook.Reinstall()
        hook.Reinstall()
        Check(hook.Handles.Length = 1, "Replacement must remove the previous hook")
        Check(hook.Filter.Owned.Has(0x27), "Replacing a hook must preserve held-arrow ownership")
        Check(DllCall(hook.Address, "Int", 0, "UPtr", 0x100, "Ptr", packet, "Ptr") = 1
            && hook.Requests.Count = 1, "Native callback swallows repeat without another request")
        hook.Window := 0
        Check(DllCall(hook.Address, "Int", 0, "UPtr", 0x101, "Ptr", packet, "Ptr") = 1,
            "Native callback must swallow its key-up outside the session")
        Check(hook.Filter.Owned.Count = 0 && hook.Fault = "", "Callback must finish without an exception")
        hook.Requests.Clear()
        hook.Window := hwnd
        hook.Working := true
        Check(DllCall(hook.Address, "Int", 0, "UPtr", 0x100, "Ptr", packet, "Ptr") = 1
            && hook.Requests.Count = 0, "Busy operations must swallow but discard new requests")
        DllCall(hook.Address, "Int", 0, "UPtr", 0x101, "Ptr", packet, "Ptr")
        hook.Reinstall()
        Check(DllCall("UnhookWindowsHookEx", "Ptr", hook.Handle, "Int"), "Fixture hook must be removable")
        hook.Reinstall()
        Check(hook.Handle, "A hook removed externally must be recoverable")
        hook.Working := false
        hook.Filter.Event(0xA0, false, false, true)
        NumPut "UInt", 0x27, packet
        DllCall(hook.Address, "Int", 0, "UPtr", 0x100, "Ptr", packet, "Ptr")
        Check(hook.Rejected.Length = 1 && InStr(hook.Rejected[1].Summary, "C=1; S=1")
            && InStr(hook.Rejected[1].State, "LCtrl#"),
            "Rejected chord diagnostics must identify which Ctrl record blocks Shift")
        Check(hook.Requests.Count = 0, "Diagnostics must not change rejected chord behavior")
    }
    finally hook.Close()
}

ModifierTraceTests() {
    trace := RDPModifierTrace()
    trace.Record(0x41, false, 0, 0x1E, true, 10)
    Check(trace.Events.Length = 0, "Never retain ordinary text keys")
    trace.Record(0xA2, false, 0, 0x1D, true, 20)
    trace.Record(0xA2, true, 0x90, 0x1D, false, 30)
    Check(InStr(trace.Events[1], "LCtrl down") && InStr(trace.Events[1], "flags=0x0"),
        "Trace must distinguish physical Ctrl down")
    Check(InStr(trace.Events[2], "LCtrl up") && InStr(trace.Events[2], "flags=0x90")
        && InStr(trace.Events[2], "active=0"), "Trace must retain ignored injected up and focus context")
    snapshot := trace.Events.Clone()
    loop 50
        trace.Record(0xA0, false, 0, 0x2A, true, 30 + A_Index)
    Check(trace.Events.Length = 32 && snapshot.Length = 2, "History must stay bounded and snapshots stable")
    filter := RDPKeyFilter()
    filter.Event(0x41, false, false, false)
    filter.Event(0xA2, false, false, false)
    Check(filter.ModifierState() = "LCtrl#2", "State dump must list only modifiers and their record sequences")
}

StaleStateTests() {
    installs := [], guard := RDPHookGuard(() => installs.Push(true))
    guard.Update("stuck-native-state", 0, true)
    guard.Update("stuck-native-state", 499, true)
    Check(installs.Length = 0, "Give native key state a short release grace period")
    guard.Update("stuck-native-state", 500, true)
    Check(installs.Length = 1, "Missing key-up must not permanently block activation refresh")
    guard.Update("stuck-native-state", 1000, true)
    guard.Update("stuck-native-state", 2000, true)
    Check(installs.Length = 3, "Stuck native state must not block subsequent refreshes")

    hook := RDPKeyboardHook()
    try {
        hook.Filter.Event(0x5B, false, false, true)
        hook.Filter.Event(0xA2, false, false, true)
        hook.Filter.Event(0x27, false, false, true)
        hook.Working := true
        hook.ObserveWindow(0, 100, false)
        hook.ObserveWindow(0, 500, false)
        Check(hook.Filter.Down.Count = 3, "Focus gaps during an operation must not reset its chord")
        hook.Working := false
        hook.ObserveWindow(0, 600, false)
        hook.ObserveWindow(0, 899, false)
        Check(hook.Filter.Down.Count = 3, "Ignore transient foreground gaps")
        hook.ObserveWindow(0, 900, true)
        Check(hook.Filter.Down.Count = 3, "Native held keys defer inactive cleanup")
        hook.ObserveWindow(0, 1000, false)
        Check(hook.Filter.Down.Count = 1 && hook.Filter.Owned.Has(0x27),
            "Background recovery must clear stale modifiers but retain owned arrows")
        Check(hook.Filter.Event(0x27, false, false, true) = -1,
            "Recovery must not retrigger a long-held arrow")
        Check(hook.Filter.Event(0x27, true, false, false) = -1,
            "Owned key-up must still be swallowed after state recovery")
        Check(hook.Filter.Event(0x25, false, false, true) = 0,
            "A plain arrow must not become a shortcut from stale Win/Ctrl state")
        hook.Filter.Event(0x25, true, false, true)
        hook.Filter.Event(0x5B, false, false, true)
        hook.Filter.Event(0xA0, false, false, true)
        Check(hook.Filter.Event(0x25, false, false, true) = 3,
            "A fresh Shift chord must work after stale Ctrl recovery")
        hook.ObserveWindow(123, 1100, false)
        hook.ObserveWindow(123, 2000, false)
        Check(hook.Filter.Down.Count = 3, "Active-session chords must not be cleared by a timer")
    }
    finally hook.Close()
}

StuckCtrlBlocksShift() {
    hook := RDPKeyboardHook()
    try {
        hook.Filter.Event(0x5B, false, false, true)
        hook.Filter.Event(0xA2, false, false, true)
        Check(hook.Filter.Event(0x27, false, false, true) = 2, "Ctrl chord switches locally")
        hook.Filter.Event(0x27, true, false, false)
        hook.Filter.Event(0x5B, true, false, false)
        ; Ctrl key-up is lost and native state remains down, as in the user's
        ; v4 trace. Neither source may prevent eventual background recovery.
        hook.ObserveWindow(0, 0, true)
        hook.ObserveWindow(0, 799, true)
        Check(hook.Filter.Down.Has(0xA2), "Observe the inactive cleanup grace period")
        hook.ObserveWindow(0, 800, true)
        Check(!hook.Filter.Down.Has(0xA2), "Stuck native state must not retain stale Ctrl forever")
        hook.ObserveWindow(123, 900, true)
        hook.Filter.Event(0x5B, false, false, true)
        hook.Filter.Event(0xA0, false, false, true)
        Check(hook.Filter.Event(0x25, false, false, true) = 3,
            "Shift chord must move without manually tapping Ctrl")
        hook.Filter.Event(0x25, true, false, true)
        hook.Filter.Event(0xA2, false, false, true)
        Check(hook.Filter.Event(0x25, false, false, true) = 0,
            "Genuine Ctrl+Shift+Win remains a passthrough combination")
    }
    finally hook.Close()

    hook := RDPKeyboardHook()
    try {
        hook.Filter.Event(0xA2, false, false, true)
        hook.ObserveWindow(0, 0, true)
        ; A fresh press of the same key after leaving must replace the stale
        ; record, even if the missed release made it look like a repeat.
        hook.Filter.Event(0xA2, false, false, false)
        hook.Filter.Event(0x5B, false, false, false)
        hook.ObserveWindow(0, 800, true)
        Check(hook.Filter.Down.Has(0xA2) && hook.Filter.Down.Has(0x5B),
            "Cleanup must retain fresh modifier presses during the inactive interval")
        hook.Filter.Event(0xA0, false, false, false)
        hook.ObserveWindow(0, 1000, true)
        Check(hook.Filter.Down.Has(0xA0), "Cleanup runs only once per inactive interval")
    }
    finally hook.Close()
}
