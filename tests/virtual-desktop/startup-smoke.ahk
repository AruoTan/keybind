#Requires AutoHotkey v2.0
#SingleInstance Off

logPath := A_Args[1], childPid := 0, helperPid := 0, failure := ""
nativePlacement := A_Args.Length > 2 && A_Args[3] = "--placement"
try {
    ; The caller copies only the compiled main EXE to an empty directory.
    ; Optional DLL load failure must not interrupt the original startup path.
    Run '"' A_Args[2] '" /ErrorStdOut=UTF-8', , , &childPid
    Sleep 1500
    if !ProcessExist(childPid)
        throw Error("Compiled main exited during startup")
    diagnostic := FileRead(EnvGet("LOCALAPPDATA") "\keybind\virtual-desktop.log", "UTF-8")
    if !InStr(diagnostic, "Virtual desktop init; diagnostics=cleanup-v2; PID=" childPid ";")
        throw Error("Compiled main did not log its cleanup diagnostic marker and PID")
    placement := FileRead(EnvGet("LOCALAPPDATA") "\keybind\window-placement.log", "UTF-8")
    if !InStr(placement, "Ready; PID=" childPid "; mode=pre-show-only;")
        throw Error("Pre-show-only placement must initialize even when the virtual desktop DLL is missing")
    if nativePlacement {
        if !RegExMatch(placement, "Native pre-show ready; ABI=3; PID=" childPid
            "; x64 hook installed; x86-host-pid=(\d+)", &match)
            throw Error("Compiled main did not initialize the native placement bridge")
        helperPid := Integer(match[1])
        if !ProcessExist(helperPid)
            throw Error("Compiled main's x86 placement host exited early")
    }
    DetectHiddenWindows true
    if !WinExist("Keybind.KeePassImeBridge.v1 ahk_pid " childPid)
        throw Error("Existing KeePass bridge did not initialize")
    for hwnd in WinGetList("ahk_pid " childPid) {
        if WinGetClass("ahk_id " hwnd) = "#32770"
            throw Error("Compiled main displayed an unhandled error dialog")
    }
}
catch as err {
    failure := err.Message "`n" err.Stack
}
finally {
    if childPid && ProcessExist(childPid)
        ProcessClose childPid
    if helperPid {
        ProcessWaitClose helperPid, 3
        if ProcessExist(helperPid)
            failure .= "`nNative x86 host survived its controller's termination"
    }
}
if failure != "" {
    FileAppend "FAIL: " failure "`n", logPath, "UTF-8"
    ExitApp 1
}
FileAppend "PASS: compiled main logs its PID and starts without the virtual-desktop DLL; KeePass and placement available; native-placement=" nativePlacement "; native host exits after controller termination`n", logPath, "UTF-8"
ExitApp 0
