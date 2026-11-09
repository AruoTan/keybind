#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk
#Include %A_LineFile%/../../../src/modules/remote-desktop/remote-desktop.ahk

logPath := A_Args[1]
try {
    count := 0
    for test in [IndependentSwitch, CarryGroup, EmptySource, PinnedAndMinimized,
        TransferFailure, GroupPropagationFailure, QueryFailure, StorageNameFailure,
        ExternalDesktopChange, DisconnectedMonitor, RestartRecovery, ExternalDrag,
        NoWindowAndWrongMonitor, IndicatorMonitor, ClosedWindow, ReusedHandle,
        UnrelatedQueryFailure, RemovedStorage, CarrySwitchFailure, FailedRollbackRecovery,
        UntrackedStoredWindow, ThirdMonitorIndependence, LastNativeDesktop,
        ExternalMoveDuringRollback, PinChangedInStorage, RealFocusRestore, NativeMonitorDiscovery,
        ForegroundChangeDuringPreparation, PreparationReentry, RecoveryDuringPreparation,
        HiddenOwnerWindows, HiddenOwnerNewDialog, UnassignedWindows] {
        test.Call()
        count += 1
    }
    FileAppend "PASS: " count " monitor workspace scenarios; native discovery on " MonitorGetCount()
        . " monitor(s); independent switching uses simulated displays`n", logPath, "UTF-8"
}
catch as err {
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}
ExitApp 0

ForegroundChangeDuringPreparation() {
    r := MonitorRig(), windows := ChangingForegroundFixture(r.Native)
    r.Api.Windows := windows
    r.Windows := windows
    r.Controller.Windows := windows
    state := NavigationState(r)
    windows.Change := true
    Check(VDNavigateWithIndicator(state, true, 1) = "no-window" && r.Native.Moves = 0,
        "Preparation must not replace the originally captured window with a new foreground window")
    Check(!state.Navigating && !r.Controller.Busy, "A cancelled request must release both guards")
    windows.Active := 101
    state.Indicator := ForegroundIndicatorFixture(windows)
    Check(VDNavigateWithIndicator(state, true, 1) = "no-window" && r.Native.Moves = 0,
        "Keep the original capture through indicator setup and controller dispatch")
}

class ChangingForegroundFixture extends MonitorWindowsFixture {
    Change := false
    Capture(known := 0) {
        group := super.Capture(known)
        if this.Change
            this.Change := false, this.Active := 102
        return group
    }
}

class ForegroundIndicatorFixture extends MonitorIndicatorFixture {
    __New(windows) {
        super.__New()
        this.Windows := windows
    }
    Begin() {
        revision := super.Begin()
        this.Windows.Active := 102
        return revision
    }
}

PreparationReentry() {
    for move in [false, true] {
        native := PreparationNativeFixture(), windows := MonitorWindowsFixture(native)
        displays := MonitorFixture(), api := VDMonitorApi(native, windows, displays)
        api.Prepare()
        r := {Native: native, Windows: windows, Displays: displays, Api: api,
            Controller: VDController(api, windows, 0, 0)}
        native.State := NavigationState(r), native.Displays := displays
        native.Move := move, native.Arm := true
        Check(VDNavigateWithIndicator(native.State, true, 1) = "moved")
        Check(native.NestedResult = "busy" && api.Selected = "left"
            && native.Locations[102] = api.Parking && native.Locations[201] = native.Host,
            "Drop a second Ctrl/Shift request before it changes the prepared monitor")
        Check(!native.State.Navigating && !r.Controller.Busy)
    }
}

RecoveryDuringPreparation() {
    global VirtualDesktopState
    previous := IsSet(VirtualDesktopState) ? VirtualDesktopState : 0
    native := PreparationNativeFixture(), windows := MonitorWindowsFixture(native)
    displays := MonitorFixture(), api := VDMonitorApi(native, windows, displays)
    api.Prepare()
    r := {Native: native, Windows: windows, Displays: displays, Api: api,
        Controller: VDController(api, windows, 0, 0, (*) => 0)}
    VirtualDesktopState := NavigationState(r)
    native.State := VirtualDesktopState, native.Displays := displays
    native.Recovery := true, native.Arm := true
    try {
        Check(VDNavigateWithIndicator(VirtualDesktopState, true, 1) = "failed")
        Check(native.HostDuringRecovery = native.Host && api.Host = native.Host,
            "Recovery must not reset monitor state while preparation is in progress")
        Check(!VirtualDesktopState.Navigating && !r.Controller.Busy,
            "Preparation failures must release the guard")
        VDMonitorRefresh()
        Check(api.Host = "" && !VirtualDesktopState.Navigating,
            "Recovery must acquire the same guard and run after the failed request")
    }
    finally VirtualDesktopState := previous
}

class PreparationNativeFixture extends MonitorNativeFixture {
    Arm := false
    Recovery := false
    WindowId(hwnd, allowUnassigned := false) {
        if this.Arm {
            this.Arm := false
            SetTimer this.Interrupt.Bind(this), -10
            Sleep 80
        }
        return super.WindowId(hwnd, allowUnassigned)
    }
    Interrupt(*) {
        if this.Recovery {
            this.Displays.Layout := "changed"
            VDMonitorRefresh()
            this.HostDuringRecovery := this.State.Monitors.Host
        } else {
            this.Displays.Selected := "right"
            this.NestedResult := VDNavigateWithIndicator(this.State, this.Move, 1)
        }
    }
}

HiddenOwnerWindows() {
    proxy := Gui(, "Keybind hidden framework owner")
    app := Gui("+Owner" proxy.Hwnd, "Keybind visible owned app")
    sibling := Gui("+Owner" proxy.Hwnd, "Keybind independent owned app")
    dialog := Gui("+Owner" app.Hwnd, "Keybind owned modal fixture")
    native := MonitorNativeFixture()
    native.Locations := Map(proxy.Hwnd, native.Host, app.Hwnd, native.Host,
        sibling.Hwnd, native.Host, dialog.Hwnd, native.Host)
    windows := MonitorRealWindowsFixture(native), displays := MonitorFixture()
    api := VDMonitorApi(native, windows, displays), controller := VDController(api, windows, 0, 0)
    try {
        app.Show("NoActivate w240 h100"), sibling.Show("NoActivate w240 h100")
        dialog.Show("NoActivate w180 h80")
        Check(windows.Ordinary(app.Hwnd) && !windows.Ordinary(proxy.Hwnd))
        api.Prepare()
        Check(api.Groups.Count = 2 && api.Groups[app.Hwnd].Group.Members.Length = 2,
            "A hidden framework owner must not hide or merge its independent visible application groups")
        Check(controller.Switch(1) = "switched" && native.Locations[app.Hwnd] = api.Parking
            && native.Locations[dialog.Hwnd] = api.Parking && native.Locations[sibling.Hwnd] = api.Parking
            && native.Locations[proxy.Hwnd] = native.Host)
        Check(controller.Switch(-1) = "switched")
        WinActivate "ahk_id " dialog.Hwnd
        Check(WinWaitActive("ahk_id " dialog.Hwnd, , 1))
        group := windows.Capture()
        Check(group.Root.Hwnd = app.Hwnd && group.Members.Length = 2,
            "Capture and inventory must resolve the same application root under a hidden proxy")
        Check(controller.Move(1) = "moved" && native.Locations[app.Hwnd] = native.Host
            && native.Locations[dialog.Hwnd] = native.Host && native.Locations[sibling.Hwnd] = api.Parking,
            "Carry the active visible app and its dialog without carrying its independent sibling")
    }
    finally {
        api.Reset()
        dialog.Destroy(), app.Destroy(), sibling.Destroy(), proxy.Destroy()
    }
}

HiddenOwnerNewDialog() {
    owner := Gui(, "Keybind hidden known owner")
    dialog := Gui("+Owner" owner.Hwnd, "Keybind newly opened owned dialog")
    native := MonitorNativeFixture(), native.Locations := Map(owner.Hwnd, native.Host)
    windows := MonitorRealWindowsFixture(native), displays := MonitorFixture()
    api := VDMonitorApi(native, windows, displays), controller := VDController(api, windows, 0, 0)
    try {
        owner.Show("NoActivate w240 h100")
        api.Prepare()
        Check(controller.Switch(1) = "switched")
        owner.Hide()
        native.Locations[dialog.Hwnd] := api.Parking
        dialog.Show("NoActivate w180 h80")
        api.Prepare()
        Check(api.Groups[owner.Hwnd].Group.Members.Length = 2,
            "Refresh visible dialogs of a valid hidden owner already tracked by the workspace")
        Check(windows.Owner(dialog.Hwnd, api.Groups) = owner.Hwnd
            && api.WindowId(dialog.Hwnd) = api.WindowId(owner.Hwnd),
            "Ownership queries and refreshed groups must share the known hidden root")
        recorded := api.Groups[owner.Hwnd].Group.Root
        api.Groups[owner.Hwnd].Group.Root := {Hwnd: owner.Hwnd, Pid: 0, Thread: recorded.Thread}
        try Check(windows.Owner(dialog.Hwnd, api.Groups) = dialog.Hwnd,
            "A stale identity must never authorize a hidden owner as the application root")
        finally api.Groups[owner.Hwnd].Group.Root := recorded
        Check(controller.Switch(-1) = "switched" && native.Locations[dialog.Hwnd] = native.Host
            && native.Locations[owner.Hwnd] = native.Host,
            "The dialog must return with its hidden owner even without implicit native propagation")
    }
    finally {
        api.Reset()
        dialog.Destroy(), owner.Destroy()
    }
}

Check(value, message := "Monitor assertion failed") {
    if !value
        throw Error(message)
}

MonitorRig() {
    native := MonitorNativeFixture(), windows := MonitorWindowsFixture(native)
    monitors := MonitorFixture(), api := VDMonitorApi(native, windows, monitors)
    errors := [], controller := VDController(api, windows, 0, 0, (message) => errors.Push(message))
    api.Prepare()
    return {Native: native, Windows: windows, Displays: monitors, Api: api,
        Controller: controller, Errors: errors}
}

IndependentSwitch() {
    r := MonitorRig(), left := r.Api.Current(), host := r.Native.Current()
    Check(r.Controller.Switch(1) = "switched")
    Check(r.Native.Current() = host && r.Native.Locations[101] = r.Api.Parking
        && r.Native.Locations[201] = host, "Switch only the pointer monitor, without a native Go")
    Check(r.Api.Snapshot().Length = 2, "An occupied source must survive")
    r.Displays.Selected := "right", r.Api.Prepare()
    right := r.Api.Current()
    Check(right != left && r.Api.Snapshot().Length = 1, "Each monitor has an independent order")
    Check(r.Controller.Switch(1) = "switched")
    Check(r.Native.Locations[101] = r.Api.Parking && r.Native.Locations[201] = r.Api.Parking)
    r.Displays.Selected := "left", r.Api.Prepare()
    Check(r.Controller.Switch(-1) = "switched" && r.Api.Current() = left)
    Check(r.Native.Locations[101] = host && r.Native.Locations[201] = r.Api.Parking,
        "Returning on the left must leave the right workspace unchanged")
    Check(r.Api.Snapshot().Length = 1 && r.Api.Index(left) = 0, "Collect only the empty source")
}

CarryGroup() {
    r := MonitorRig(), r.Native.Locations[111] := r.Native.Host, r.Windows.Owners[111] := 101
    r.Api.Prepare()
    Check(r.Controller.Move(1) = "moved")
    Check(r.Api.Snapshot().Length = 2 && r.Api.Index(r.Api.Current()) = 1)
    Check(r.Native.Locations[101] = r.Native.Host && r.Native.Locations[111] = r.Native.Host
        && r.Native.Locations[102] = r.Api.Parking && r.Native.Locations[201] = r.Native.Host,
        "Carry only the selected owner/dialog group, preserving another window of the same process")
    for transfer in r.Native.Transfers
        Check(transfer.Hwnd != 101 && transfer.Hwnd != 111, "Carried windows must never be deactivated by parking")
}

EmptySource() {
    r := MonitorRig(), r.Native.Locations.Delete(102), r.Api.Prepare()
    Check(r.Controller.Move(-1) = "moved")
    Check(r.Api.Snapshot().Length = 1 && r.Api.Index(r.Api.Current()) = 0,
        "Left creation/reorder and immediate empty-source removal must renumber this monitor only")
    Check(r.Native.Locations[201] = r.Native.Host && r.Native.Ids.Length = 1,
        "Carrying the only window must not park/deactivate it or create an unused native desktop")
}

PinnedAndMinimized() {
    r := MonitorRig(), r.Native.Pins[101] := true
    r.Windows.Minimized[102] := true
    Check(r.Controller.Switch(1) = "switched")
    Check(r.Native.Locations[101] = r.Native.Host && r.Native.Pins[101], "Pinned windows stay pinned and visible")
    Check(r.Api.Snapshot().Length = 2 && r.Native.Locations[102] = r.Api.Parking,
        "Minimized windows still occupy the departed workspace")
    Check(r.Controller.Switch(-1) = "switched" && r.Windows.Minimized[102], "Switching must not restore a minimized window")
    r := MonitorRig(), r.Native.Locations.Delete(102), r.Native.Pins[101] := true, r.Api.Prepare()
    Check(r.Controller.Move(1) = "pinned" && r.Api.Snapshot().Length = 1)
    Check(r.Controller.Switch(1) = "switched" && r.Api.Snapshot().Length = 1,
        "Pinned windows must not keep an otherwise empty workspace alive")
}

TransferFailure() {
    r := MonitorRig(), source := r.Api.Current(), r.Native.FailMove := 2
    Check(r.Controller.Switch(1) = "failed")
    Check(r.Api.Current() = source && r.Native.Locations[101] = r.Native.Host
        && r.Native.Locations[102] = r.Native.Host && r.Native.Locations[201] = r.Native.Host,
        "A partial transfer must restore every affected source window")
    Check(!r.Controller.Busy && r.Api.Snapshot().Length = 1)
}

GroupPropagationFailure() {
    r := MonitorRig(), r.Native.Locations[111] := r.Native.Host, r.Windows.Owners[111] := 101
    r.Native.Propagate := true, r.Native.FailAfterMove := true, r.Api.Prepare()
    Check(r.Controller.Switch(1) = "failed")
    Check(r.Native.Locations[101] = r.Native.Host && r.Native.Locations[111] = r.Native.Host,
        "Rollback must include dialogs moved implicitly before the native call reports failure")
}

QueryFailure() {
    r := MonitorRig(), r.Native.FailQuery := 102
    try {
        r.Api.Prepare()
        throw Error("Expected unknown ownership to stop preparation")
    }
    catch as err
        Check(InStr(err.Message, "Injected ownership"))
    Check(r.Native.Moves = 0 && r.Native.Ids.Length = 1, "Uncertain ownership must not move any screen")
}

UnassignedWindows() {
    for device in ["left", "right"] {
        for tracked in [false, true] {
            r := MonitorRig(), r.Displays.Selected := device, r.Api.Prepare()
            hwnd := tracked ? (device = "left" ? 102 : 201) : 103
            r.Native.Locations[hwnd] := "", r.Displays.Devices[hwnd] := device
            Check(r.Api.WindowId(hwnd, true) = "",
                "An unassigned root must never match an uncreated storage desktop")
            r.Api.Prepare()
            Check(!r.Api.Groups.Has(hwnd),
                "Skip confirmed unassigned windows, including previously tracked roots, on either monitor")
            other := device = "left" ? 201 : 101
            Check(r.Controller.Switch(1) = "switched" && r.Native.Locations[other] = r.Native.Host,
                "An unassigned window must not block switching or move another monitor's windows")
            Check(r.Native.Locations[hwnd] = "" && r.Api.WindowId(hwnd, true) = "",
                "Leave unassigned windows untouched and exclude them from occupancy")
            for change in r.Native.Transfers
                Check(change.Hwnd != hwnd, "Never transfer a window without an assigned desktop")
        }
    }
}

StorageNameFailure() {
    r := MonitorRig(), r.Native.FailName := true
    Check(r.Controller.Switch(1) = "failed" && r.Native.Ids.Length = 1 && r.Native.Moves = 0,
        "A storage desktop must be recoverable by name before any window enters it")
}

ExternalDesktopChange() {
    r := MonitorRig(), r.Controller.Switch(1)
    r.Native.Ids.Push("other"), r.Native.Desktop := "other"
    Check(r.Api.Prepare())
    Check(r.Native.Desktop = "other" && r.Native.Locations[101] = r.Native.Host
        && r.Api.Host = "other" && r.Api.Parking = "", "External native switching resets workspaces without overriding the chosen desktop")
}

DisconnectedMonitor() {
    r := MonitorRig(), r.Controller.Switch(1)
    r.Displays.Layout := "single", r.Displays.Number := 1
    Check(!r.Api.Prepare())
    Check(r.Native.Locations[101] = r.Native.Host && r.Api.Parking = "" && r.Api.Views.Count = 0,
        "Disconnecting a screen must return parked windows before selecting the single-screen backend")
}

RestartRecovery() {
    r := MonitorRig(), r.Controller.Switch(1), storage := r.Api.Parking
    replacement := VDMonitorApi(r.Native, r.Windows, r.Displays)
    replacement.Recover()
    Check(r.Native.Ids.Length = 1 && r.Native.Locations[101] = r.Native.Host,
        "The next launch must recover windows even without the old process's in-memory state")
    r := MonitorRig(), r.Controller.Switch(1)
    r.Native.Ids.Push("other"), r.Native.Ids.RemoveAt(1), r.Native.Desktop := "other"
    VDMonitorApi(r.Native, r.Windows, r.Displays).Recover()
    Check(r.Native.Locations[101] = "other", "A deleted original host needs an available fallback")
}

ExternalDrag() {
    r := MonitorRig(), r.Displays.Devices[101] := "right", r.Api.Prepare()
    Check(r.Controller.Switch(1) = "switched")
    Check(r.Native.Locations[101] = r.Native.Host && r.Native.Locations[102] = r.Api.Parking,
        "A window dragged to another screen must belong to that screen's current workspace")
}

NoWindowAndWrongMonitor() {
    r := MonitorRig(), state := NavigationState(r), r.Windows.Active := 0
    Check(VDNavigateWithIndicator(state, true, 1) = "no-window" && r.Native.Moves = 0)
    r.Windows.Active := 201
    Check(VDNavigateWithIndicator(state, true, 1) = "wrong-monitor" && r.Native.Moves = 0,
        "Carrying a window must not act on a different screen from the pointer")
    state.Controller.Busy := true
    Check(VDNavigateWithIndicator(state, false, 1) = "busy" && r.Native.Moves = 0)
}

IndicatorMonitor() {
    r := MonitorRig(), state := NavigationState(r)
    Check(VDNavigateWithIndicator(state, false, 1) = "switched")
    Check(state.Indicator.Numbers[1] = 2 && state.Indicator.Work.Left = -1920,
        "The final number and popup must belong to the pointer monitor, including negative coordinates")
}

ClosedWindow() {
    r := MonitorRig(), r.Controller.Switch(1), r.Native.Locations.Delete(101), r.Native.Locations.Delete(102)
    r.Api.Prepare()
    Check(r.Controller.Switch(-1) = "switched" && r.Api.Snapshot().Length = 1,
        "Closed parked windows must not block cleanup or be moved by recycled records")
}

ReusedHandle() {
    r := MonitorRig(), r.Controller.Switch(1)
    r.Windows.Generations[101] := 2, r.Native.Locations[101] := r.Native.Host, r.Api.Prepare()
    Check(r.Api.Groups[101].Desktop = r.Api.Current(), "A reused HWND must be adopted as a new current window")
}

CarrySwitchFailure() {
    r := MonitorRig(), source := r.Api.Current(), r.Native.FailMove := 1
    Check(r.Controller.Move(1) = "failed" && r.Api.Current() = source)
    Check(r.Api.WindowId(101) = source && r.Native.Locations[101] = r.Native.Host
        && r.Native.Locations[102] = r.Native.Host && r.Api.Snapshot().Length = 1,
        "A failed switch must roll staged ownership back without moving the carried window")
}

FailedRollbackRecovery() {
    r := MonitorRig(), r.Native.FailMoves := Map(2, true, 3, true)
    Check(r.Controller.Switch(1) = "failed" && r.Api.Faulted)
    Check(r.Api.Prepare() && !r.Api.Faulted && r.Native.Locations[101] = r.Native.Host
        && r.Native.Locations[102] = r.Native.Host && r.Api.Snapshot().Length = 1,
        "Failed rollback must recover storage before accepting another request")
}

UntrackedStoredWindow() {
    r := MonitorRig(), r.Controller.Switch(1)
    r.Native.Locations[103] := r.Api.Parking
    try {
        r.Api.Prepare()
        throw Error("Expected an untracked stored window to require recovery")
    }
    catch as err
        Check(InStr(err.Message, "Untracked window"))
    Check(r.Api.Faulted && r.Api.Prepare() && r.Native.Locations[103] = r.Native.Host,
        "A new independent window on storage must be recovered, never lost through empty cleanup")
}

ThirdMonitorIndependence() {
    r := MonitorRig(), r.Displays.Number := 3, r.Displays.Layout := "triple"
    r.Displays.Devices[301] := "third", r.Native.Locations[301] := r.Native.Host
    r.Displays.Selected := "third", r.Api.Prepare()
    Check(r.Controller.Switch(1) = "switched")
    third := r.Api.Current()
    r.Displays.Selected := "left", r.Api.Prepare()
    Check(r.Controller.Move(1) = "moved" && r.Native.Locations[201] = r.Native.Host
        && r.Native.Locations[301] = r.Api.Parking, "A third screen's workspace must remain independent")
    r.Displays.Selected := "third", r.Api.Prepare()
    Check(r.Api.Current() = third && r.Api.Snapshot().Length = 2)
}

LastNativeDesktop() {
    for restart in [false, true] {
        r := MonitorRig(), r.Controller.Switch(1), storage := r.Api.Parking
        r.Native.Remove(r.Native.Host, storage)
        if restart
            VDMonitorApi(r.Native, r.Windows, r.Displays).Recover()
        else
            r.Api.Prepare()
        Check(r.Native.Ids.Length = 1 && r.Native.Current() = storage
            && r.Native.Locations[101] = storage && r.Native.Name(storage) = "Desktop 1",
            "Recovery must preserve the last native desktop when the original host was closed")
    }
}

ExternalMoveDuringRollback() {
    r := MonitorRig(), r.Native.Ids.Push("other"), r.Native.FailMove := 2
    r.Native.OnFailure := () => r.Native.Locations[101] := "other"
    Check(r.Controller.Switch(1) = "failed" && r.Api.Faulted)
    Check(r.Native.Locations[101] = "other" && r.Api.Prepare() && r.Native.Locations[101] = "other",
        "Rollback and recovery must preserve a window moved externally to an unrelated native desktop")
}

PinChangedInStorage() {
    r := MonitorRig(), r.Native.Locations.Delete(102), r.Api.Prepare()
    Check(r.Controller.Switch(1) = "switched")
    r.Native.Pins[101] := true
    Check(r.Controller.Switch(-1) = "switched" && r.Controller.Switch(1) = "switched")
    Check(r.Api.Snapshot().Length = 1 && r.Native.Pins[101], "Removing a pinned-only workspace must retain pin state")
    r.Native.Pins[101] := false, r.Api.Prepare()
    Check(r.Api.WindowId(101) = r.Api.Current() && r.Native.Locations[101] = r.Native.Host
        && r.Native.Locations[201] = r.Native.Host,
        "Unpinning a stored window must return it to an existing workspace without changing another screen")
}

UnrelatedQueryFailure() {
    r := MonitorRig(), r.Native.FailQuery := 201
    r.Api.Prepare()
    Check(r.Controller.Switch(1) = "switched" && r.Native.Locations[201] = r.Native.Host,
        "An unrelated screen's ownership failure must not move its windows or block this screen")
}

RemovedStorage() {
    r := MonitorRig(), r.Controller.Switch(1)
    r.Native.Remove(r.Api.Parking, r.Native.Host)
    r.Api.Prepare()
    Check(r.Api.Parking = "" && r.Api.Snapshot().Length = 1,
        "External removal of storage must discard stale workspace membership")
    Check(r.Controller.Switch(1) = "switched", "Navigation must recover after an external storage removal")
}

RealFocusRestore() {
    first := Gui(, "Keybind left-screen focus fixture"), second := Gui(, "Keybind right-screen fixture")
    next := Gui(, "Keybind next workspace fixture"), input := first.AddEdit("w180")
    native := MonitorNativeFixture(), windows := MonitorRealWindowsFixture(native), monitors := MonitorFixture()
    native.Locations := Map(first.Hwnd, native.Host, second.Hwnd, native.Host)
    native.RealWindows := true
    monitors.Devices := Map(first.Hwnd, "left", second.Hwnd, "right", next.Hwnd, "left")
    api := VDMonitorApi(native, windows, monitors), history := RDPFocusHistory()
    controller := VDController(api, windows, 0, 0)
    try {
        first.Show("x100 y100 w220 h100"), second.Show("x500 y100 w220 h100")
        WinActivate "ahk_id " first.Hwnd
        Check(WinWaitActive("ahk_id " first.Hwnd, , 1))
        api.Prepare()
        focus := MonitorFocusFixture(first.Hwnd, windows, history), focus.Shell := second.Hwnd
        Check(controller.Switch(1, focus) = "switched")
        Check(!DllCall("IsWindowVisible", "Ptr", first.Hwnd, "Int")
            && DllCall("IsWindowVisible", "Ptr", second.Hwnd, "Int"))
        native.Locations[next.Hwnd] := native.Host
        next.Show("x100 y100 w220 h100")
        WinActivate "ahk_id " next.Hwnd
        Check(WinWaitActive("ahk_id " next.Hwnd, , 1))
        api.Prepare()
        focus := MonitorFocusFixture(next.Hwnd, windows, history), focus.Shell := second.Hwnd
        Check(controller.Switch(-1, focus) = "switched")
        Check(DllCall("GetForegroundWindow", "Ptr") = first.Hwnd,
            "The shared focus handoff must restore the selected monitor's remembered window")
        input.Focus()
        SendText "monitor-input-ok"
        Sleep 50
        Check(input.Value = "monitor-input-ok" && DllCall("IsWindowVisible", "Ptr", second.Hwnd, "Int"),
            "Typing must work without a click while the other screen's window remains visible")
    }
    finally {
        api.Reset()
        first.Destroy(), second.Destroy(), next.Destroy()
    }
}

class MonitorFocusFixture extends RDPSwitchFocus {
    ShellWindows() => [this.Shell]
}

class MonitorRealWindowsFixture extends VDWindows {
    __New(native) => this.Native := native
    Applications() {
        result := []
        for hwnd in this.Native.Locations {
            if DllCall("IsWindow", "Ptr", hwnd, "Int")
                result.Push(this.Token(hwnd))
        }
        return result
    }
}

NativeMonitorDiscovery() {
    fixture := Gui(), monitors := VDMonitors()
    try {
        fixture.Show("w200 h100")
        device := monitors.Window(fixture.Hwnd), work := monitors.Work(device)
        context := DllCall("GetThreadDpiAwarenessContext", "Ptr")
        Check(monitors.Count() = MonitorGetCount() && monitors.Pointer() != ""
            && work.Right > work.Left && work.Bottom > work.Top && InStr(monitors.Signature(), device),
            "Native device, pointer, bounds and topology discovery must agree")
        Check(DllCall("AreDpiAwarenessContextsEqual", "Ptr", context,
            "Ptr", DllCall("GetThreadDpiAwarenessContext", "Ptr"), "Int"),
            "Pointer selection must restore the caller's DPI awareness")
    }
    finally fixture.Destroy()
}

NavigationState(r) => {Controller: r.Controller, MonitorController: r.Controller,
    NativeController: VDController(r.Native, r.Windows), Monitors: r.Api, Indicator: MonitorIndicatorFixture()}

class MonitorIndicatorFixture extends VDIndicator {
    __New() {
        super.__New()
        this.Numbers := [], this.Work := 0
    }
    Show(number, revision := -1) {
        this.Numbers.Push(number), this.Work := this.Viewport.Call()
        return true
    }
}

class MonitorFixture {
    __New() {
        this.Number := 2, this.Selected := "left", this.Layout := "dual"
        this.Devices := Map(101, "left", 102, "left", 201, "right")
    }
    Count() => this.Number
    Signature() => this.Layout
    Pointer() => this.Selected
    Window(hwnd) => this.Devices.Has(hwnd) ? this.Devices[hwnd] : "left"
    Work(device) => device = "left" ? {Left: -1920, Top: 0, Right: 0, Bottom: 1080}
        : {Left: 0, Top: 0, Right: 1920, Bottom: 1080}
}

class MonitorWindowsFixture extends VDWindows {
    __New(native) {
        this.Native := native, this.Active := 101, this.Owners := Map(), this.Minimized := Map()
        this.Generations := Map()
    }
    Owner(hwnd, known := 0) => this.Owners.Has(hwnd) ? this.Owners[hwnd] : hwnd
    Token(hwnd) => {Hwnd: hwnd, Pid: this.Generations.Get(hwnd, 1), Thread: 1}
    Valid(token) => this.Native.Locations.Has(token.Hwnd) && token.Pid = this.Generations.Get(token.Hwnd, 1)
    Applications() {
        result := []
        for hwnd in this.Native.Locations
            result.Push(this.Token(hwnd))
        return result
    }
    Group(hwnd, known := 0) {
        root := this.Token(this.Owner(hwnd)), members := [root]
        for child in this.Native.Locations {
            if child != root.Hwnd && this.Owner(child) = root.Hwnd
                members.Push(this.Token(child))
        }
        return {Root: root, Active: this.Token(hwnd), Members: members}
    }
    Capture(known := 0) => this.Active ? this.Group(this.Active, known) : 0
    StillActive(group) => group.Active.Hwnd = this.Active
    Focus(group) => true
    Describe(token) => "fixture " token.Hwnd
}

class MonitorNativeFixture {
    __New() {
        this.Host := "{00000000-0000-0000-0000-000000000001}", this.Desktop := this.Host
        this.Ids := [this.Host], this.Locations := Map(101, this.Host, 102, this.Host, 201, this.Host)
        this.Pins := Map(), this.Names := Map(), this.Moves := 0, this.Serial := 0
        this.FailMove := 0, this.FailQuery := 0, this.FailName := false
        this.Propagate := false, this.FailAfterMove := false
        this.Transfers := [], this.FailMoves := Map()
        this.OnFailure := 0
    }
    Snapshot() => this.Ids.Clone()
    Current() => this.Desktop
    Index(id) {
        for index, candidate in this.Ids {
            if candidate = id
                return index - 1
        }
        throw Error("Missing native fixture desktop")
    }
    WindowId(hwnd, allowUnassigned := false) {
        if hwnd = this.FailQuery
            throw Error("Injected ownership query failure")
        id := this.Locations[hwnd]
        if id = "" && !allowUnassigned
            throw Error("Window has no assigned virtual desktop")
        return id
    }
    Pinned(hwnd) => this.Pins.Has(hwnd) && this.Pins[hwnd]
    Create() {
        id := "storage-" (++this.Serial)
        this.Ids.Push(id)
        return id
    }
    Name(id, value?) {
        if this.FailName
            throw Error("Injected name failure")
        if IsSet(value)
            this.Names[id] := value
        return this.Names.Has(id) ? this.Names[id] : "Desktop"
    }
    MoveWindow(hwnd, id) {
        this.Moves += 1
        this.Transfers.Push({Hwnd: hwnd, Target: id})
        if this.Moves = this.FailMove || this.FailMoves.Has(this.Moves) {
            if IsObject(this.OnFailure)
                this.OnFailure.Call()
            throw Error("Injected transfer failure")
        }
        this.Locations[hwnd] := id
        if this.HasOwnProp("RealWindows") && this.RealWindows {
            DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", id = this.Host ? 8 : 0, "Int")
            started := A_TickCount
            while !!DllCall("IsWindowVisible", "Ptr", hwnd, "Int") != (id = this.Host) {
                if A_TickCount - started > 1000
                    throw Error("Fixture window visibility timed out")
                Sleep 10
            }
        }
        if this.Propagate && hwnd = 101
            this.Locations[111] := id
        if this.FailAfterMove {
            this.FailAfterMove := false
            throw Error("Injected failure after owned-window propagation")
        }
    }
    Remove(id, fallback) {
        this.Index(fallback)
        for hwnd, location in this.Locations {
            if location = id
                this.MoveWindow(hwnd, fallback)
        }
        this.Ids.RemoveAt(this.Index(id) + 1)
        if this.Desktop = id
            this.Desktop := fallback
    }
}
