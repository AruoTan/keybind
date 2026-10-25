#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%/../../src/modules/virtual-desktop/virtual-desktop.ahk

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
        UnassignedActiveWindow, WindowClosesDuringOccupancy, CleanupPinQueryFailure] {
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
        return id
    }
    Reorder(id, index) {
        this.Check("Reorder")
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

class FakeWindows {
    __New(api) {
        this.Api := api, this.Active := true, this.CanFocus := true
        this.Members := [101], this.AfterCapture := 0, this.OnScan := 0
        this.ScanCount := 0
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
