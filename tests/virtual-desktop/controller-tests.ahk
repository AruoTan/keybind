#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk

logPath := A_Args.Length ? A_Args[1] : A_ScriptDir "\controller-tests.log"
try {
    count := 0
    for test in [NoWindow, PinnedWindow, ExistingNeighbor, LeftBoundary, RightBoundary,
        OccupiedSource, UnknownWindow, PinQueryFailure, CreationFailure, ReorderFailure,
        MoveFailure, SilentMoveFailure, SwitchFailure, SilentSwitchFailure, PartialSwitchFailure,
        PartialGroupFailure, OwnedDialogPropagation, FocusFailure, RemovalFailure,
        ExternalReorder, LateApplication, ConcurrentRequest, InvalidDirection, ClosedWindow,
        ForegroundChanged, FixedWindowDoesNotOccupy, PinnedGroupMember, LastDesktopGuard,
        HotkeyPressLatch, FailureIncludesContext, UnassignedWindow,
        UnassignedActiveWindow, WindowClosesDuringOccupancy, CleanupPinQueryFailure,
        UntrackedBackgroundFrame, UntrackedFrameStateGuards, UntrackedFrameErrorGuards,
        AssignedFrameStillOccupies, FrameReturnsBeforeRemoval, FrameInspectionFailure,
        SwitchExisting, SwitchBoundaries, SwitchWithoutWindow, SwitchFailureOnly,
        SwitchQueryFailure, SwitchBusy, SwitchInvalidDirection, SwitchPressLatch,
        SwitchEmptySource, SwitchSingleEmptyDesktop, SwitchPinnedSource, SwitchUnassignedSource,
        SwitchUntrackedSource, SwitchUnknownSource, SwitchLateApplication, SwitchCleanupFailure,
        SwitchBoundaryFailures, SwitchOccupiedCreatedFailure, SwitchPartialFailure,
        SwitchConcurrentRequests, SwitchOrderChangedAfterGo, SwitchContinuousCreation,
        SwitchFocusBeforeCreatedFailure, SwitchFocusAfterCreatedFailure,
        SwitchFocusOrder, SwitchFocusBeforeFailure, SwitchFocusAfterFailure,
        SwitchFocusApiFailure, SwitchFocusBoundary, SwitchFocusOrderChanged, SwitchFocusCloseFailure,
        SwitchHiddenSourceProtection, SwitchSourceProtectionFailure] {
        test.Call()
        count += 1
    }
    FileAppend "PASS: " count " controller scenarios`n", logPath, "UTF-8"
    ExitApp 0
}
catch as err {
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}

Assert(condition, message := "Assertion failed") {
    if !condition
        throw Error(message, -1)
}

SwitchExisting() {
    r := Rig(["A", "B", "C"], "B")
    Assert(r.Controller.Switch(-1) = "switched" && r.Api.Desktop = "A")
    Assert(r.Controller.Switch(1) = "switched" && r.Api.Desktop = "B")
    Assert(r.Api.Locations[101] = "B" && VDOrder(r.Api.Ids) = "B|C|",
        "Switching back must collect the empty source without moving the app")
    for call in r.Api.Calls
        Assert(call != "MoveWindow" && call != "Create" && call != "Reorder",
            "Existing neighbors must be used without moving windows or creating desktops")
}

SwitchBoundaries() {
    r := Rig(["A", "B"])
    Assert(r.Controller.Switch(-1) = "switched")
    Assert(VDOrder(r.Api.Ids) = "N1|A|B|" && r.Api.Desktop = "N1")
    Assert(r.Api.Locations[101] = "A", "Left creation must not carry the source window")
    r := Rig(["A", "B"], "B")
    Assert(r.Controller.Switch(1) = "switched")
    Assert(VDOrder(r.Api.Ids) = "A|B|N1|" && r.Api.Desktop = "N1" && !r.Controller.Busy)
}

SwitchWithoutWindow() {
    r := Rig(), r.Windows.Active := false
    Assert(r.Controller.Switch(1) = "switched", "Ctrl+Win must work with no active app")
    Assert(r.Api.Desktop = "B" && r.Api.Locations[101] = "A")
}

SwitchFailureOnly() {
    r := Rig(), r.Api.SilentGo := true
    Assert(r.Controller.Switch(1) = "failed")
    Assert(r.Api.Desktop = "A" && VDOrder(r.Api.Ids) = "A|B|")
    Assert(r.Api.Locations[101] = "A" && !r.Controller.Busy && r.Messages.Length = 1)
}

SwitchQueryFailure() {
    r := Rig(), r.Api.Fail := "Snapshot"
    Assert(r.Controller.Switch(1) = "failed")
    Assert(r.Api.Desktop = "A" && !r.Controller.Busy)
}

SwitchBusy() {
    r := Rig(), r.Controller.Busy := true
    Assert(r.Controller.Switch(1) = "busy" && r.Api.Calls.Length = 0)
}

SwitchInvalidDirection() {
    r := Rig(), rejected := false
    try r.Controller.Switch(0)
    catch ValueError
        rejected := true
    Assert(rejected && !r.Controller.Busy && r.Api.Calls.Length = 0)
}

SwitchPressLatch() {
    global VirtualDesktopState
    r := Rig(["A", "B", "C"])
    VirtualDesktopState := {Controller: r.Controller, Held: Map("Left", false, "Right", false)}
    try {
        VDSwitchKeyDown(1, "Right")
        VDSwitchKeyDown(1, "Right")
        VDKeyDown(1, "Right")
        Assert(r.Api.Desktop = "B" && r.Api.Locations[101] = "A",
            "Repeat and changing modifiers while held must not move or switch again")
        VDKeyUp("Right")
        VDSwitchKeyDown(1, "Right")
        Assert(r.Api.Desktop = "C")
    }
    finally VirtualDesktopState := 0
}

SwitchEmptySource() {
    r := Rig(["A", "B", "C"], "B"), r.Api.Locations.Clear(), r.Windows.Active := false
    r.Api.Locations[102] := "A"
    Assert(r.Controller.Switch(1) = "switched")
    Assert(VDOrder(r.Api.Ids) = "A|C|" && r.Api.Desktop = "C" && r.Windows.ScanCount = 2)
    Assert(r.Controller.Switch(-1) = "switched")
    Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Desktop = "A",
        "Resolve GUIDs again after deleting the middle desktop")
}

SwitchSingleEmptyDesktop() {
    for direction in [-1, 1] {
        r := Rig(["A"]), r.Api.Locations.Clear(), r.Windows.Active := false
        Assert(r.Controller.Switch(direction) = "switched")
        Assert(VDOrder(r.Api.Ids) = "N1|" && r.Api.Desktop = "N1",
            "Create a target before collecting the sole empty desktop")
        Assert(r.Api.Locations.Count = 0 && r.Windows.ScanCount = 2)
    }
}

SwitchPinnedSource() {
    r := Rig(), r.Api.Pins[101] := true
    Assert(r.Controller.Switch(1) = "switched")
    Assert(VDOrder(r.Api.Ids) = "B|" && r.Api.Pins[101],
        "Pinned windows must not occupy the source or lose their pinned state")
    for call in r.Api.Calls
        Assert(call != "MoveWindow", "Ctrl+Win must never move a pinned window")
}

SwitchUnassignedSource() {
    r := Rig(), r.Api.Locations[101] := "", r.Api.PinFailures[101] := true
    Assert(r.Controller.Switch(1) = "switched" && VDOrder(r.Api.Ids) = "B|")
}

SwitchUntrackedSource() {
    r := MissingFrameRig(), r.Api.Locations.Delete(101)
    Assert(r.Controller.Switch(1) = "switched" && VDOrder(r.Api.Ids) = "B|",
        "Switch cleanup must reuse the guarded background-frame exception")
}

SwitchUnknownSource() {
    for pinFailure in [false, true] {
        r := Rig()
        if pinFailure
            r.Api.PinFailures[101] := true
        else
            r.Api.Locations[101] := "?"
        Assert(r.Controller.Switch(1) = "switched-retained")
        Assert(VDOrder(r.Api.Ids) = "A|B|" && r.Api.Desktop = "B" && !r.Controller.Busy)
        Assert(r.Messages.Length = 1 && InStr(r.Messages[1], "occupancy check failed"))
    }
}

SwitchLateApplication() {
    r := Rig(), r.Api.Locations.Clear()
    r.Windows.OnScan := (number) => number = 2 ? r.Api.Locations[102] := "A" : 0
    Assert(r.Controller.Switch(1) = "switched")
    Assert(VDOrder(r.Api.Ids) = "A|B|" && r.Windows.ScanCount = 2,
        "A new source application between scans must prevent deletion")
}

SwitchCleanupFailure() {
    r := Rig(), r.Api.Locations.Clear(), r.Api.Fail := "Remove"
    Assert(r.Controller.Switch(1) = "switched-retained")
    Assert(r.Api.Desktop = "B" && VDOrder(r.Api.Ids) = "A|B|" && !r.Controller.Busy)
    Assert(r.Messages.Length = 1)
}

SwitchBoundaryFailures() {
    for direction in [-1, 1] {
        for failure in ["Create", "Reorder", "SilentReorder", "Go", "SilentGo"] {
            if direction = 1 && (failure = "Reorder" || failure = "SilentReorder")
                continue
            r := Rig(["A"])
            if failure = "SilentGo"
                r.Api.SilentGo := true
            else if failure = "SilentReorder"
                r.Api.SilentReorder := true
            else
                r.Api.Fail := failure
            Assert(r.Controller.Switch(direction) = "failed")
            Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Desktop = "A" && !r.Controller.Busy,
                "Failed boundary operations must reclaim only their empty created desktop")
            Assert(r.Api.Locations[101] = "A")
            for call in r.Api.Calls {
                Assert(call != "MoveWindow")
                if failure = "Create" || failure = "Reorder" || failure = "SilentReorder"
                    Assert(call != "Go", "Creation/reorder failure must stop before switching")
            }
        }
    }
}

SwitchOccupiedCreatedFailure() {
    r := Rig(["A"]), r.Api.Fail := "Go"
    r.Api.AfterCreate := (id) => r.Api.Locations[102] := id
    Assert(r.Controller.Switch(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|N1|" && r.Api.Locations[102] = "N1",
        "Failed switching must not reclaim a created desktop that acquired an app")
}

SwitchPartialFailure() {
    r := Rig(["A"]), r.Api.Locations.Clear(), r.Api.ThrowAfterGo := true
    Assert(r.Controller.Switch(1) = "failed")
    Assert(r.Api.Desktop = "N1" && VDOrder(r.Api.Ids) = "A|N1|",
        "An unconfirmed partial switch must not delete either desktop")
}

SwitchConcurrentRequests() {
    r := Rig(), results := []
    r.Windows.OnScan := (number) => results.Push(r.Controller.Switch(-1), r.Controller.Move(-1))
    Assert(r.Controller.Switch(1) = "switched")
    Assert(results.Length = 2 && results[1] = "busy" && results[2] = "busy" && !r.Controller.Busy)
}

SwitchOrderChangedAfterGo() {
    r := Rig(), r.Api.Locations.Clear()
    r.Api.AfterGo := (id) => r.Api.Ids.Push("external")
    Assert(r.Controller.Switch(1) = "switched-retained")
    Assert(VDOrder(r.Api.Ids) = "A|B|external|" && r.Api.Desktop = "B",
        "External order changes must stop source cleanup")
}

SwitchContinuousCreation() {
    r := Rig(["A"])
    for expected in ["N1", "N2", "N3"] {
        Assert(r.Controller.Switch(1) = "switched" && r.Api.Desktop = expected)
        Assert(VDOrder(r.Api.Ids) = "A|" expected "|" && r.Api.Locations[101] = "A",
            "Continuous boundary navigation must collect only the empty previous target")
    }
    Assert(r.Controller.Switch(-1) = "switched" && r.Api.Desktop = "A")
    Assert(VDOrder(r.Api.Ids) = "A|", "Return to the original application desktop without moving it")
}

SwitchFocusBeforeCreatedFailure() {
    r := Rig(["A"]), focus := FakeSwitchFocus(), focus.FailBefore := true
    Assert(r.Controller.Switch(-1, focus) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Desktop = "A")
    Assert(VDOrder(focus.Calls) = "before|close|" && !r.Controller.Busy)
}

SwitchFocusAfterCreatedFailure() {
    r := Rig(["A"]), r.Api.Locations.Clear(), focus := FakeSwitchFocus(), focus.FailAfter := true
    Assert(r.Controller.Switch(-1, focus) = "switched-unfocused")
    Assert(VDOrder(r.Api.Ids) = "N1|A|" && r.Api.Desktop = "N1" && r.Windows.ScanCount = 0,
        "Unrestored target focus must retain the empty source")
    Assert(VDOrder(focus.Calls) = "before|after|close|" && !r.Controller.Busy)
}

class HiddenSourceFocus extends FakeSwitchFocus {
    __New() {
        super.__New()
        this.Unknown := false
    }
    SourceOccupied(api, source) {
        Assert(api.Current() != source, "Check the original window after switching")
        if this.Unknown
            throw Error("Original hidden application ownership is unknown")
        return true
    }
}

SwitchHiddenSourceProtection() {
    r := Rig(), r.Api.Locations.Clear(), focus := HiddenSourceFocus()
    Assert(r.Controller.Switch(1, focus) = "switched")
    Assert(VDOrder(r.Api.Ids) = "A|B|" && r.Windows.ScanCount = 0,
        "A known hidden source application must retain its desktop")
    Assert(VDOrder(focus.Calls) = "before|after|close|")
}

SwitchSourceProtectionFailure() {
    r := Rig(), r.Api.Locations.Clear(), focus := HiddenSourceFocus(), focus.Unknown := true
    Assert(r.Controller.Switch(1, focus) = "switched-retained")
    Assert(VDOrder(r.Api.Ids) = "A|B|" && r.Api.Desktop = "B" && !r.Controller.Busy)
}

class FakeSwitchFocus {
    __New() {
        this.Calls := [], this.FailBefore := false, this.FailAfter := false
        this.FailClose := false, this.Reorder := false
    }
    Before(api, source, target) {
        Assert(api.Current() = source, "Release focus before switching desktop")
        this.Calls.Push("before")
        if this.Reorder
            api.Ids.Push("external")
        if this.FailBefore
            throw Error("Cannot release RDP focus")
    }
    After(api, source, target) {
        Assert(api.Current() = target, "Restore input only after reaching the target desktop")
        this.Calls.Push("after")
        return !this.FailAfter
    }
    Close() {
        this.Calls.Push("close")
        if this.FailClose
            throw Error("Focus cleanup fixture failed")
    }
}

SwitchFocusOrder() {
    r := Rig(), focus := FakeSwitchFocus()
    r.Windows.OnScan := (number) => Assert(VDOrder(focus.Calls) = "before|after|",
        "Source cleanup must follow target focus restoration")
    Assert(r.Controller.Switch(1, focus) = "switched")
    Assert(VDOrder(focus.Calls) = "before|after|close|" && !r.Controller.Busy)
    Assert(r.Api.Locations[101] = "A", "Focus handoff must not move the RDP window")
}
SwitchFocusBeforeFailure() {
    r := Rig(), focus := FakeSwitchFocus(), focus.FailBefore := true
    Assert(r.Controller.Switch(1, focus) = "failed" && r.Api.Desktop = "A")
    Assert(VDOrder(focus.Calls) = "before|close|" && !r.Controller.Busy)
}
SwitchFocusAfterFailure() {
    r := Rig(), focus := FakeSwitchFocus(), focus.FailAfter := true
    Assert(r.Controller.Switch(1, focus) = "switched-unfocused" && r.Api.Desktop = "B")
    Assert(VDOrder(focus.Calls) = "before|after|close|" && r.Messages.Length = 1)
}
SwitchFocusApiFailure() {
    r := Rig(), focus := FakeSwitchFocus(), r.Api.Fail := "Go"
    Assert(r.Controller.Switch(1, focus) = "failed" && r.Api.Desktop = "A")
    Assert(VDOrder(focus.Calls) = "before|close|")
}
SwitchFocusBoundary() {
    r := Rig(["A"]), focus := FakeSwitchFocus()
    Assert(r.Controller.Switch(1, focus) = "switched")
    Assert(r.Api.Desktop = "N1" && r.Api.Locations[101] = "A")
    Assert(VDOrder(focus.Calls) = "before|after|close|",
        "New desktops need the same focus handoff as existing neighbors")
}
SwitchFocusOrderChanged() {
    r := Rig(), focus := FakeSwitchFocus(), focus.Reorder := true
    Assert(r.Controller.Switch(1, focus) = "failed" && r.Api.Desktop = "A")
    Assert(VDOrder(focus.Calls) = "before|close|")
}
SwitchFocusCloseFailure() {
    r := Rig(), focus := FakeSwitchFocus(), focus.FailClose := true
    Assert(r.Controller.Switch(1, focus) = "switched" && !r.Controller.Busy)
    Assert(r.Messages.Length = 1, "Focus cleanup failure must be reported without trapping Busy")
}

FailureIncludesContext() {
    r := Rig()
    r.Windows.AfterCapture := RaiseCaptureError
    Assert(r.Controller.Move(1) = "failed")
    Assert(r.Messages.Length = 1)
    Assert(InStr(r.Messages[1], "fixtureBuffer"), "Error report must identify the unassigned variable")
    Assert(InStr(r.Messages[1], "CaptureFixture"), "Error report must identify the failing function")
    Assert(!r.Controller.Busy && r.Api.Calls.Length = 0)
}

RaiseCaptureError() {
    throw UnsetError("Test local variable is unassigned", "CaptureFixture", "fixtureBuffer")
}

Rig(ids := 0, current := "A") {
    api := FakeApi(IsObject(ids) ? ids : ["A", "B"], current)
    windows := FakeWindows(api)
    messages := []
    controller := VDController(api, windows, 0, 0, (message) => messages.Push(message))
    return {Api: api, Windows: windows, Controller: controller, Messages: messages}
}

class FakeApi {
    __New(ids, current) {
        this.Ids := ids.Clone(), this.Desktop := current
        this.Locations := Map(101, current), this.Pins := Map()
        this.Calls := [], this.Fail := "", this.Serial := 0
        this.SilentMove := false, this.SilentGo := false, this.ThrowAfterGo := false
        this.AfterMove := 0, this.OnWindowId := 0, this.PinFailures := Map()
        this.AfterCreate := 0, this.AfterGo := 0, this.SilentReorder := false
    }
    Check(name) {
        this.Calls.Push(name)
        if this.Fail = name {
            this.Fail := ""
            throw Error("Injected " name " failure")
        }
    }
    Snapshot() {
        this.Check("Snapshot")
        return this.Ids.Clone()
    }
    Index(id) {
        for index, candidate in this.Ids {
            if candidate = id
                return index - 1
        }
        throw Error("Missing fake desktop")
    }
    Current() => this.Desktop
    WindowId(hwnd, allowUnassigned := false) {
        this.Check("WindowId")
        if IsObject(this.OnWindowId)
            this.OnWindowId.Call(hwnd)
        id := this.Locations[hwnd]
        if id = "" && !allowUnassigned
            throw Error("Window has no assigned virtual desktop")
        if id = "?"
            throw Error("Unknown desktop ownership")
        return id
    }
    Pinned(hwnd) {
        this.Check("Pinned")
        if this.PinFailures.Has(hwnd)
            throw Error("Injected pin query failure")
        return this.Pins.Has(hwnd) && this.Pins[hwnd]
    }
    Create() {
        this.Check("Create")
        id := "N" (++this.Serial)
        this.Ids.Push(id)
        if IsObject(this.AfterCreate)
            this.AfterCreate.Call(id)
        return id
    }
    Reorder(id, index) {
        this.Check("Reorder")
        if this.SilentReorder
            return
        this.Ids.RemoveAt(this.Index(id) + 1)
        this.Ids.InsertAt(index + 1, id)
    }
    MoveWindow(hwnd, id) {
        this.Check("MoveWindow")
        this.Index(id)
        if !this.SilentMove
            this.Locations[hwnd] := id
        this.SilentMove := false
        if IsObject(this.AfterMove)
            this.AfterMove.Call(hwnd, id)
    }
    Go(id) {
        this.Check("Go")
        this.Index(id)
        if !this.SilentGo
            this.Desktop := id
        this.SilentGo := false
        if IsObject(this.AfterGo)
            this.AfterGo.Call(id)
        if this.ThrowAfterGo {
            this.ThrowAfterGo := false
            throw Error("Go changed desktop before reporting failure")
        }
    }
    Remove(id, fallback) {
        this.Check("Remove")
        Assert(this.Ids.Length > 1 && id != fallback, "Invalid fake removal")
        this.Index(fallback)
        for hwnd, location in this.Locations {
            Assert(location != id || this.Pinned(hwnd), "Removed an occupied desktop")
        }
        this.Ids.RemoveAt(this.Index(id) + 1)
    }
}

class FakeWindows extends VDWindows {
    __New(api) {
        this.Api := api, this.Active := true, this.CanFocus := true
        this.Members := [101], this.AfterCapture := 0, this.OnScan := 0
        this.ScanCount := 0
        this.Frames := Map(), this.FrameFailure := false
    }
    Token(hwnd) => {Hwnd: hwnd, Pid: 1, Thread: 1}
    Capture() {
        if !this.Active
            return 0
        members := []
        for hwnd in this.Members
            members.Push(this.Token(hwnd))
        group := {Root: members[1], Active: members[-1], Members: members}
        if IsObject(this.AfterCapture)
            this.AfterCapture.Call()
        return group
    }
    Valid(token) => this.Api.Locations.Has(token.Hwnd)
    FrameState(token) {
        if this.FrameFailure
            throw Error("Injected frame inspection failure")
        return this.Frames.Has(token.Hwnd) ? this.Frames[token.Hwnd] : 0
    }
    Describe(token) => Format("HWND 0x{:X}; PID {}; class Fixture", token.Hwnd, token.Pid)
    StillActive(group) => this.Active
    Focus(group) => this.CanFocus
    Applications() {
        this.ScanCount += 1
        if IsObject(this.OnScan)
            this.OnScan.Call(this.ScanCount)
        result := []
        for hwnd, id in this.Api.Locations
            result.Push(this.Token(hwnd))
        return result
    }
}

NoWindow() {
    r := Rig(), r.Windows.Active := false
    Assert(r.Controller.Move(1) = "no-window")
    Assert(r.Api.Calls.Length = 0, "No foreground window must cause no DLL calls")
}
PinnedWindow() {
    r := Rig(), r.Api.Pins[101] := true
    Assert(r.Controller.Move(1) = "pinned")
    Assert(VDOrder(r.Api.Ids) = "A|B|" && r.Api.Locations[101] = "A")
}
ExistingNeighbor() {
    r := Rig()
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "B|" && r.Api.Desktop = "B" && r.Api.Locations[101] = "B")
}
LeftBoundary() {
    r := Rig(["A", "B"])
    Assert(r.Controller.Move(-1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "N1|B|", "Left insertion/deletion must preserve identities")
    Assert(r.Api.Desktop = "N1" && r.Api.Locations[101] = "N1")
}
RightBoundary() {
    r := Rig(["A"])
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "N1|" && r.Api.Desktop = "N1")
}
OccupiedSource() {
    r := Rig(), r.Api.Locations[102] := "A" ; Represents a minimized/cloaked app too.
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "A|B|", "Other source windows must retain source")
}
UnknownWindow() {
    r := Rig(), r.Api.Locations[102] := "?"
    Assert(r.Controller.Move(1) = "moved-retained")
    Assert(VDOrder(r.Api.Ids) = "A|B|")
    Assert(r.Messages.Length = 1 && InStr(r.Messages[1], "occupancy check failed"))
    Assert(InStr(r.Messages[1], "HWND 0x66"), "Unknown ownership must identify the blocker")
}
PinQueryFailure() {
    r := Rig(), r.Api.Fail := "Pinned"
    Assert(r.Controller.Move(1) = "failed")
    Assert(r.Api.Locations[101] = "A" && r.Api.Desktop = "A")
}
CreationFailure() {
    r := Rig(["A"]), r.Api.Fail := "Create"
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|")
}
ReorderFailure() {
    r := Rig(["A"]), r.Api.Fail := "Reorder"
    Assert(r.Controller.Move(-1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|", "Failed left insertion must reclaim only new empty desktop")
}
MoveFailure() {
    r := Rig(["A"]), r.Api.Fail := "MoveWindow"
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Locations[101] = "A")
}
SilentMoveFailure() {
    r := Rig(["A"]), r.Api.SilentMove := true
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Desktop = "A")
}
SwitchFailure() {
    r := Rig(["A"]), r.Api.Fail := "Go"
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Locations[101] = "A")
}
SilentSwitchFailure() {
    r := Rig(), r.Api.SilentGo := true
    Assert(r.Controller.Move(1) = "failed")
    Assert(r.Api.Locations[101] = "A" && r.Api.Desktop = "A")
}
PartialSwitchFailure() {
    r := Rig(), r.Api.ThrowAfterGo := true
    Assert(r.Controller.Move(1) = "failed")
    Assert(r.Api.Locations[101] = "A" && r.Api.Desktop = "A")
}
PartialGroupFailure() {
    r := Rig(), r.Windows.Members.Push(102), r.Api.Locations[102] := "A"
    r.Api.AfterMove := (hwnd, id) => r.Api.Fail := hwnd = 101 ? "MoveWindow" : ""
    Assert(r.Controller.Move(1) = "failed")
    Assert(r.Api.Locations[101] = "A" && r.Api.Locations[102] = "A")
}
OwnedDialogPropagation() {
    r := Rig(), r.Windows.Members.Push(102), r.Api.Locations[102] := "A"
    r.Api.AfterMove := (hwnd, id) => r.Api.Locations[102] := id
    Assert(r.Controller.Move(1) = "moved")
    Assert(r.Api.Locations[101] = "B" && r.Api.Locations[102] = "B")
}
FocusFailure() {
    r := Rig(), r.Windows.CanFocus := false
    Assert(r.Controller.Move(1) = "moved-retained")
    Assert(VDOrder(r.Api.Ids) = "A|B|" && r.Api.Desktop = "B")
}
RemovalFailure() {
    r := Rig(), r.Api.Fail := "Remove"
    Assert(r.Controller.Move(1) = "moved-retained")
    Assert(r.Api.Locations[101] = "B" && VDOrder(r.Api.Ids) = "A|B|")
}
ExternalReorder() {
    r := Rig()
    r.Api.AfterMove := (hwnd, id) => r.Api.Reorder("B", 0)
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "B|A|", "External reorder must never delete wrong index")
    Assert(r.Api.Locations[101] = "A")
}
LateApplication() {
    r := Rig()
    r.Windows.OnScan := (number) => number = 2 ? r.Api.Locations[102] := "A" : 0
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "A|B|", "Second occupancy scan must catch new application")
}
ConcurrentRequest() {
    r := Rig(), results := []
    r.Api.AfterMove := (hwnd, id) => results.Push(r.Controller.Move(-1))
    Assert(r.Controller.Move(1) = "moved")
    Assert(results.Length = 1 && results[1] = "busy")
    Assert(!r.Controller.Busy, "Busy flag must clear after completion")
}
InvalidDirection() {
    r := Rig(), failed := false
    try r.Controller.Move(0)
    catch ValueError
        failed := true
    Assert(failed && !r.Controller.Busy)
}
ClosedWindow() {
    r := Rig(), r.Windows.AfterCapture := () => r.Api.Locations.Delete(101)
    Assert(r.Controller.Move(1) = "no-window")
    Assert(VDOrder(r.Api.Ids) = "A|B|")
}
ForegroundChanged() {
    r := Rig(["A"]), r.Windows.AfterCapture := () => r.Windows.Active := false
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|" && r.Api.Locations[101] = "A")
}
FixedWindowDoesNotOccupy() {
    r := Rig(), r.Api.Locations[102] := "A", r.Api.Pins[102] := true
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "B|" && r.Api.Pins[102])
}
PinnedGroupMember() {
    r := Rig(), r.Windows.Members.Push(102), r.Api.Locations[102] := "A", r.Api.Pins[102] := true
    Assert(r.Controller.Move(1) = "pinned")
    Assert(r.Api.Locations[101] = "A")
}
LastDesktopGuard() {
    r := Rig(["A"])
    Assert(!r.Controller.RemoveIfEmpty("A", "A", ["A"]))
    Assert(VDOrder(r.Api.Ids) = "A|")
}
HotkeyPressLatch() {
    global VirtualDesktopState
    r := Rig(["A", "B", "C"]), r.Api.Locations[102] := "A"
    VirtualDesktopState := {Controller: r.Controller, Held: Map("Left", false, "Right", false)}
    try {
        VDKeyDown(1, "Right")
        Assert(r.Api.Desktop = "B")
        VDKeyDown(1, "Right")
        Assert(r.Api.Desktop = "B", "Held-key repeat must not move again")
        r.Controller.Busy := true
        VDKeyDown(-1, "Left")
        r.Controller.Busy := false
        VDKeyDown(-1, "Left")
        Assert(r.Api.Desktop = "B", "Press ignored while busy must remain latched")
        VDKeyUp("Left")
        VDKeyDown(-1, "Left")
        Assert(r.Api.Desktop = "A", "Release must arm the next physical press")
    }
    finally {
        VirtualDesktopState := 0
    }
}

UnassignedWindow() {
    r := Rig(), r.Api.Locations[102] := "", r.Api.PinFailures[102] := true
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "B|", "Confirmed unassigned windows must not block cleanup")
    Assert(r.Windows.ScanCount = 2, "Unassigned windows must be handled on both scans")
}
UnassignedActiveWindow() {
    r := Rig(["A"]), r.Api.Locations[101] := ""
    Assert(r.Controller.Move(1) = "failed")
    Assert(VDOrder(r.Api.Ids) = "A|", "Unassigned foreground windows must not create desktops")
}
WindowClosesDuringOccupancy() {
    r := Rig(), r.Api.Locations[102] := "?"
    r.Api.OnWindowId := (hwnd) => hwnd = 102 ? CloseQueriedWindow(r.Api, hwnd) : 0
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "B|", "A closed window must not block source cleanup")
}
CloseQueriedWindow(api, hwnd) {
    api.Locations.Delete(hwnd)
    throw Error("Window closed during query")
}
CleanupPinQueryFailure() {
    r := Rig(), r.Api.Locations[102] := "A", r.Api.PinFailures[102] := true
    Assert(r.Controller.Move(1) = "moved-retained")
    Assert(VDOrder(r.Api.Ids) = "A|B|", "Live windows with failed pin queries must retain the source")
    Assert(r.Messages.Length = 1 && InStr(r.Messages[1], "occupancy check failed"))
    Assert(InStr(r.Messages[1], "HWND 0x66") && InStr(r.Messages[1], "class Fixture"),
        "Cleanup errors must identify the blocker without window contents")
}

MissingFrameRig() {
    r := Rig(), r.Api.Locations[102] := "?"
    r.Api.OnWindowId := (hwnd) => hwnd = 102 ? MissingFrameQuery(hwnd) : 0
    r.Windows.Frames[102] := {Cloak: 1, CoreWindow: false, Minimized: false, Foreground: false}
    return r
}

MissingFrameQuery(hwnd) {
    throw VDWindowQueryError(hwnd, 0x8002802B)
}

UntrackedBackgroundFrame() {
    r := MissingFrameRig()
    Assert(r.Controller.Move(1) = "moved")
    Assert(VDOrder(r.Api.Ids) = "B|" && r.Windows.ScanCount = 2,
        "Confirmed inactive untracked frames must not block either cleanup scan")
    Assert(r.Messages.Length = 0, "Recognized background frames must not show an error")
}

UntrackedFrameStateGuards() {
    for flags in [0, 2, 3, 4, 5, 6, 7, 8] {
        r := MissingFrameRig(), r.Windows.Frames[102].Cloak := flags
        Assert(r.Controller.Move(1) = "moved-retained" && VDOrder(r.Api.Ids) = "A|B|",
            "Shell, inherited, visible and unknown cloak states must retain the desktop")
    }
    for property in ["CoreWindow", "Minimized", "Foreground"] {
        r := MissingFrameRig(), r.Windows.Frames[102].%property% := true
        Assert(r.Controller.Move(1) = "moved-retained" && VDOrder(r.Api.Ids) = "A|B|",
            "Real UWP content, minimized or active frames must retain the desktop")
    }
    r := MissingFrameRig(), r.Windows.Frames.Clear()
    Assert(r.Controller.Move(1) = "moved-retained",
        "Missing views outside ApplicationFrameHost must not be ignored")
}

UntrackedFrameErrorGuards() {
    for failure in [Error("GetWindowDesktopId query failed", , "HRESULT 0x8002802B"),
        VDWindowQueryError(102, 0x80004005), VDWindowQueryError(102, 0x80070005),
        VDWindowQueryError(102, 1), VDWindowQueryError(999, 0x8002802B)] {
        r := MissingFrameRig()
        r.Api.OnWindowId := (hwnd) => hwnd = 102 ? RaiseFrameQuery(failure) : 0
        Assert(r.Controller.Move(1) = "moved-retained" && VDOrder(r.Api.Ids) = "A|B|",
            "Unrelated failures and mismatched HWNDs must not authorize removal")
    }
}

RaiseFrameQuery(failure) {
    throw failure
}

AssignedFrameStillOccupies() {
    r := MissingFrameRig(), r.Api.OnWindowId := 0, r.Api.Locations[102] := "A"
    Assert(r.Controller.Move(1) = "moved" && VDOrder(r.Api.Ids) = "A|B|",
        "Even an app-cloaked frame must retain its successfully identified desktop")
}

FrameReturnsBeforeRemoval() {
    r := MissingFrameRig()
    r.Windows.OnScan := (number) => number = 2 ? r.Windows.Frames[102].CoreWindow := true : 0
    Assert(r.Controller.Move(1) = "moved-retained" && VDOrder(r.Api.Ids) = "A|B|",
        "The second scan must detect a frame acquiring real app content")
}

FrameInspectionFailure() {
    r := MissingFrameRig(), r.Windows.FrameFailure := true
    Assert(r.Controller.Move(1) = "moved-retained" && VDOrder(r.Api.Ids) = "A|B|")
    Assert(InStr(r.Messages[1], "HRESULT 0x8002802B"),
        "Failed frame inspection must preserve the original ownership diagnostic")
}
