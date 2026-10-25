#Requires AutoHotkey v2.0
#SingleInstance Off

logPath := A_Args[1], childPid := 0, failure := ""
try {
    ; The caller copies only the compiled main EXE to an empty directory.
    ; Optional DLL load failure must not interrupt the original startup path.
    Run '"' A_Args[2] '" /ErrorStdOut=UTF-8', , , &childPid
    Sleep 1500
    if !ProcessExist(childPid)
        throw Error("Compiled main exited during startup")
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
}
if failure != "" {
    FileAppend "FAIL: " failure "`n", logPath, "UTF-8"
    ExitApp 1
}
FileAppend "PASS: compiled main starts without its optional DLL; KeePass bridge stays available`n", logPath, "UTF-8"
ExitApp 0
