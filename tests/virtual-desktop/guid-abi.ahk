#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%/../../src/modules/virtual-desktop/virtual-desktop.ahk

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
    FileAppend "PASS: actual x64 GUID return/input ABI, HWND width, zero GUID and native error guards`n", logPath, "UTF-8"
    ExitApp 0
}
catch as err {
    FileAppend "FAIL: " err.Message "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}
