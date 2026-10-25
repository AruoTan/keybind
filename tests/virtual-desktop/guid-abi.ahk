#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk

logPath := A_Args[1]
try {
    api := VDNative(A_Args[2])
    expected := "{FEDCBA98-7654-3210-89AB-CDEF01020304}"
    ids := api.Snapshot()
    if ids.Length != 1 || ids[1] != expected || api.Current() != expected
        throw Error("GUID return value or desktop index round trip failed")
    if api.WindowId(101) != expected || api.Pinned(101)
        throw Error("Pointer-sized HWND or pin query failed")
    failures := 0
    try api.Id(99)
    catch
        failures += 1
    try api.Pinned(999)
    catch
        failures += 1
    try api.Create()
    catch
        failures += 1
    try api.Remove(expected, expected)
    catch
        failures += 1
    if failures != 4
        throw Error("Native error handling or last-desktop guard failed")

    fallback := VDManagerFixture(A_Args[2])
    if fallback.WindowId(102, true) != ""
        throw Error("S_OK/GUID_NULL must be classified as unassigned")
    if fallback.WindowId(104, true) != expected || fallback.WindowId(104) != expected
        throw Error("A successful public query must recover the desktop GUID")
    ExpectFailure(() => fallback.WindowId(102), "Window has no assigned virtual desktop")
    ExpectFailure(() => fallback.WindowId(103, true), "HRESULT 0x80004005")
    ExpectFailure(() => fallback.WindowId(105, true), "HRESULT 0x00000001")
    ExpectFailure(() => api.Id(99), "No desktop GUID returned")
    api.Procs["GetDesktopIdByNumber"] := DllCall("GetProcAddress", "Ptr", api.Module,
        "AStr", "InvalidGuidReturn", "Ptr")
    ExpectFailure(() => api.Id(0), "Invalid GUID return ABI")
    FileAppend "PASS: actual x64 GUID return/input ABI, HWND width, zero GUID, HRESULT/unassigned distinction and native error guards`n", logPath, "UTF-8"
    ExitApp 0
}
catch as err {
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}

ExpectFailure(action, expected) {
    try action.Call()
    catch as err {
        if !InStr(VDErrorText(err), expected)
            throw Error("Unexpected native error: " VDErrorText(err))
        return
    }
    throw Error("Expected native failure: " expected)
}

class VDManagerFixture extends VDNative {
    Manager() => DllCall(DllCall("GetProcAddress", "Ptr", this.Module,
        "AStr", "GetTestDesktopManager", "Ptr"), "Ptr")
}
