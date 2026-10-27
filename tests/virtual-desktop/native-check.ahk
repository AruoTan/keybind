#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk

logPath := A_Args[1], dll := A_Args[2]
exercise := A_Args.Length >= 3 && A_Args[3] = "--exercise"
fixture := 0, api := 0, original := "", owned := []
failure := ""
try {
    FileAppend("Environment: Windows " A_OSVersion "; UBR "
        . RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "UBR", "unknown")
        . "; AutoHotkey " A_AhkVersion "; pointer bytes " A_PtrSize "`n", logPath, "UTF-8")
    api := VDProbeNative(dll), owned := api.Owned
    baseline := api.Snapshot(), original := api.Current()
    fixture := Gui(, "Keybind virtual desktop verification fixture")
    fixture.AddText(, "Temporary test window. No application content is used.")
    fixture.Show("w420 h100")
    Sleep 200
    if api.WindowId(fixture.Hwnd) != original || api.ManagerWindowId(fixture.Hwnd) != original
        || api.Pinned(fixture.Hwnd)
        throw Error("Fixture GUID/pin query failed")
    FileAppend "PASS: exports, GUID ABI/index round trips, current/window GUID, public HRESULT query and pin queries`n", logPath, "UTF-8"
    if exercise {
        ; All pre-existing desktops are preserved. The controller only leaves
        ; desktops created by this test; never use the original as its source.
        source := api.Create()
        target := api.Create()
        api.MoveWindow(fixture.Hwnd, source)
        api.Go(source)
        controller := VDController(api, VDWindows(), 2000, 100,
            (message) => FileAppend(message "`n", logPath, "UTF-8"))
        controller.Await(() => api.Current() = source && api.WindowId(fixture.Hwnd) = source)
        WinActivate "ahk_id " fixture.Hwnd
        if !WinWaitActive("ahk_id " fixture.Hwnd, , 1)
            throw Error("Cannot focus native fixture")
        if controller.Move(1) != "moved" || api.Current() != target
            throw Error("Existing-neighbor move failed")
        afterMove := api.Snapshot()
        for id in afterMove {
            if id = source
                throw Error("Empty fixture source was not removed")
        }
        ; Make the fixture desktop the left boundary, then exercise left create.
        api.Reorder(target, 0)
        controller.Await(() => api.Index(target) = 0)
        if controller.Move(-1) != "moved"
            throw Error("Left-boundary create/move/cleanup failed")
        createdLeft := api.Current()
        if api.Index(createdLeft) != 0 || api.WindowId(fixture.Hwnd) != createdLeft
            throw Error("Left-created desktop identity/order failed")
        ; Exercise Ctrl+Win behavior using only test-owned source desktops.
        ; The fixture stays on createdLeft throughout all four switches.
        if controller.Switch(-1) != "switched"
            throw Error("Left-boundary desktop-only switch failed")
        emptyLeft := api.Current()
        if api.Index(emptyLeft) != 0 || api.WindowId(fixture.Hwnd) != createdLeft
            throw Error("Desktop-only left creation moved the fixture or used the wrong position")
        if controller.Switch(1) != "switched" || api.Current() != createdLeft
            throw Error("Return from empty left desktop failed")
        for id in api.Snapshot() {
            if id = emptyLeft
                throw Error("Empty left source was not collected")
        }
        api.Reorder(createdLeft, api.Snapshot().Length - 1)
        controller.Await(() => api.Index(createdLeft) = api.Snapshot().Length - 1)
        if controller.Switch(1) != "switched"
            throw Error("Right-boundary desktop-only switch failed")
        emptyRight := api.Current()
        if api.Index(emptyRight) != api.Snapshot().Length - 1 || api.WindowId(fixture.Hwnd) != createdLeft
            throw Error("Desktop-only right creation moved the fixture or used the wrong position")
        if controller.Switch(-1) != "switched" || api.Current() != createdLeft
            throw Error("Return from empty right desktop failed")
        for id in api.Snapshot() {
            if id = emptyRight
                throw Error("Empty right source was not collected")
        }
        for id in baseline
            api.Index(id)
        FileAppend "PASS: real create, reorder, window move, switch, focus and empty-source removal`n", logPath, "UTF-8"
        FileAppend "PASS: desktop-only boundary creation in both directions, no window move and empty-source collection`n", logPath, "UTF-8"
    }
}
catch as err {
    failure := err.Message "`n" err.Stack
}
finally {
    if IsObject(fixture)
        fixture.Destroy()
    if exercise && IsObject(api) && original != "" {
        try {
            api.Go(original)
            cleanup := VDController(api, VDWindows(), 2000, 100, (message) => 0)
            cleanup.Await(() => api.Current() = original)
            for id in owned {
                present := false
                for candidate in api.Snapshot() {
                    if candidate = id
                        present := true
                }
                if present && !cleanup.RemoveIfEmpty(id, original, api.Snapshot())
                    throw Error("Test desktop retained because it is occupied")
            }
            ; Restore the baseline desktop order after temporary reordering.
            for index, id in baseline
                api.Reorder(id, index - 1)
        }
        catch as err {
            failure .= "`nNative fixture cleanup incomplete: " err.Message
        }
    }
}
if failure != "" {
    FileAppend "FAIL: " failure "`n", logPath, "UTF-8"
    ExitApp 1
}
ExitApp 0

class VDProbeNative extends VDNative {
    __New(path) {
        super.__New(path)
        this.Owned := []
    }
    Create() {
        id := super.Create()
        this.Owned.Push(id)
        return id
    }
}
