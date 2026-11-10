#Requires AutoHotkey v2.0
#SingleInstance Off
logPath := A_Args[1], folder := A_Args[2], library := 0, host := 0, existing := 0
heartbeat := 0, failure := "", fixturePid := 0
localHook := A_Args.Length > 2 && A_Args[3] = "--local-hook" ? " --local-hook" : ""
try {
    ; An HWND created before hook installation must retain its saved location.
    oldLog := logPath ".existing"
    try FileDelete oldLog
    try FileDelete oldLog ".go"
    Run '"' folder '\placement-fixture64.exe" "' oldLog '" existing' localHook, , , &existing
    deadline := A_TickCount + 3000
    while (!FileExist(oldLog) || !InStr(FileRead(oldLog), "ready")) && A_TickCount < deadline
        Sleep 10
    Check(FileExist(oldLog) && InStr(FileRead(oldLog), "ready"), "Pre-existing HWND fixture ready")
    library := DllCall("LoadLibraryExW", "Str", folder "\KeybindPlacement64.dll", "Ptr", 0, "UInt", 0x1100, "Ptr")
    Check(library, "Load x64 placement DLL")
    functions := Map()
    for name in ["Start", "Stop", "Update", "Block", "Status", "Run"] {
        functions[name] := DllCall("GetProcAddress", "Ptr", library, "AStr", "Placement" name, "Ptr")
        Check(functions[name], "Native export " name)
    }
    Check(DllCall(functions["Start"], "UInt") = 0, "Install real global CBT hook")
    heartbeat := () => DllCall(functions["Update"], "Int", 0)
    SetTimer heartbeat, 100
    Run '"' folder '\keybind-placement32.exe"', , "Hide", &host
    deadline := A_TickCount + 4000
    while DllCall(functions["Status"], "UInt", 0, "UInt") != host && A_TickCount < deadline
        Sleep 20
    Check(DllCall(functions["Status"], "UInt", 0, "UInt") = host,
        "x86 host joins x64 controller mapping and installs its hook")
    DllCall "SetCursorPos", "Int", 800, "Int", 300
    FileAppend "go", oldLog ".go"
    ProcessWaitClose existing, 3
    Check(InStr(FileRead(oldLog), "first 100 100"), "Old hidden HWND is not reclassified as new")
    for bits in [64, 32] {
        for scenario in ["regular", "restore", "destroy", "maximized", "visible", "default", "early-dialog"] {
            path := logPath "." bits "." scenario
            RunWait '"' folder '\placement-fixture' bits '.exe" "' path '" ' scenario localHook
            output := FileRead(path)
            Check(!InStr(output, "first 100 100") || scenario = "destroy" || scenario = "early-dialog", "First frame must never use saved screen: " bits "/" scenario " " output)
            if scenario = "destroy" {
                Check(InStr(output, "destroyed 1"), "Destruction during show must not leave a dangling subclass")
            } else if scenario = "maximized" {
                Check(RegExMatch(output, "m)^maximized (?:[6-9]\d\d|1[01]\d\d) 1$"),
                    "Maximization retains target-screen restore bounds: " bits " " output)
            } else if scenario = "early-dialog" {
                Check(InStr(output, "first 100 100") && RegExMatch(output, "m)^early-dialog [0-5]?\d\d \d+ 220 140 1$"),
                    "A dialog opened during the owner's first show follows its captured target, even when the pointer moves: " output)
            } else {
                Check(RegExMatch(output, "m)^first (?:[6-9]\d\d|1[01]\d\d) \d+ 240 160 1$"),
                    "First paint occurs on destination and is marked handled: " bits "/" scenario " " output)
            }
            if scenario = "regular" {
                Check(InStr(output, "reshow 100 100"), "Later move/show stays where the user put it")
                Check(RegExMatch(output, "m)^dialog [0-5]?\d\d \d+ 220 140 1$"), "Dialog follows visible owner on left screen")
                Check(InStr(output, "tool 100 100") && InStr(output, "fullscreen 0 0")
                    && InStr(output, "noactivate 100 100"), "Tools, full screen and passive windows are untouched")
            }
        }
    }
    for bits in [64, 32] {
        for scenario in ["blocked-hidden", "crash"] {
            path := logPath "." bits "." scenario
            try FileDelete path
            try FileDelete path ".go"
            Run '"' folder '\placement-fixture' bits '.exe" "' path '" ' scenario localHook, , , &fixturePid
            deadline := A_TickCount + 3000
            while (!FileExist(path) || !InStr(FileRead(path), "ready")) && A_TickCount < deadline
                Sleep 10
            Check(FileExist(path) && InStr(FileRead(path), "ready"), "Hidden HWND ready: " bits "/" scenario)
            if scenario = "blocked-hidden"
                Check(DllCall(functions["Block"], "Int", 1, "Int"), "Block after native subclass installation")
            FileAppend "go", path ".go"
            ProcessWaitClose fixturePid, 3
            Check(!ProcessExist(fixturePid), "Fixture exited: " bits "/" scenario)
            output := FileRead(path)
            if scenario = "blocked-hidden" {
                Check(InStr(output, "first 100 100 240 160 0"), "Blocked native show stays in place: " output)
                Check(DllCall(functions["Block"], "Int", 0, "Int"), "Release blocked-show guard")
            } else {
                Check(InStr(output, "crash-after-routing"), "Fixture exits during first-show commit")
                Check(DllCall(functions["Block"], "Int", 1, "Int"), "Navigation recovers after application crash")
                Check(DllCall(functions["Block"], "Int", 0, "Int"), "Release recovered guard")
            }
        }
    }
    for bits in [64, 32] {
        for scenario in ["position", "reuse", "restart", "dragged", "expired", "blocked"] {
            path := logPath ".run." bits "." scenario
            for suffix in ["", ".go", ".again"] {
                try FileDelete path suffix
            }
            Run '"' folder '\run' bits '\explorer.exe" "' path '" ' scenario localHook, , , &fixturePid
            deadline := A_TickCount + 3000
            while (!FileExist(path) || !InStr(FileRead(path), "ready")) && A_TickCount < deadline
                Sleep 10
            Check(FileExist(path) && InStr(FileRead(path), "ready"), "Run HWND ready: " bits "/" scenario)
            Check(DllCall(functions["Run"], "Str", "TEST_RIGHT", "Int"), "Publish the keypress monitor")
            DllCall "SetCursorPos", "Int", 100, "Int", 300 ; Pointer moves after the request.
            if scenario = "expired"
                Sleep 1100
            if scenario = "blocked"
                Check(DllCall(functions["Block"], "Int", 1, "Int"), "Block Run pre-show placement")
            FileAppend "go", path ".go"
            if scenario = "reuse" || scenario = "restart" || scenario = "dragged" {
                deadline := A_TickCount + 3000
                while !InStr(FileRead(path), "hidden") && A_TickCount < deadline
                    Sleep 10
                Check(InStr(FileRead(path), "hidden 0"), "Hiding Run clears its native handled marker")
                if scenario = "restart" {
                    DllCall functions["Stop"]
                    ProcessWaitClose host, 3
                    Check(DllCall(functions["Start"], "UInt") = 0, "Restart the Run controller")
                    Run '"' folder '\keybind-placement32.exe"', , "Hide", &host
                }
                Check(DllCall(functions["Run"], "Str", "TEST_LEFT", "Int"), "Publish a new request for the reused HWND")
                DllCall "SetCursorPos", "Int", 800, "Int", 300
                FileAppend "go", path ".again"
            }
            ProcessWaitClose fixturePid, 3
            Check(!ProcessExist(fixturePid), "Run fixture exited: " bits "/" scenario)
            output := FileRead(path)
            if scenario = "expired" || scenario = "blocked"
                Check(InStr(output, "first 20 548 240 160 0"), "Unrouted Run stays in place: " output)
            else if scenario = "position"
                Check(InStr(output, "first 656 590 200 120 1"), "Apply the host's pending geometry before hidden DPI layout: " output)
            else {
                expected := scenario = "dragged" ? "reused 125 310 240 160 1" : "reused 20 548 240 160 1"
                Check(InStr(output, "first 656 590 200 120 1") && InStr(output, expected)
                    && InStr(output, "unrequested 100 100 240 160 0"),
                    "Run's first frame and reused HWND preserve current margins at the destination DPI, with no unsolicited relocation: " output)
            }
            if scenario = "blocked"
                Check(DllCall(functions["Block"], "Int", 0, "Int"), "Release Run navigation guard")
        }
    }
    DllCall "SetCursorPos", "Int", 800, "Int", 300
    for bits in [64, 32] {
        path := logPath "." bits ".legacy"
        RunWait '"' folder '\placement-legacy' bits '.exe" "' path '" legacy' localHook
        output := FileRead(path)
        Check(InStr(output, "hook-module 1"), "Load hook in an application without a Common Controls v6 manifest")
        if InStr(output, "subclass-supported 0")
            Check(InStr(output, "first 100 100 240 160 0"), "Missing subclass API leaves the window in place: " output)
        else
            Check(RegExMatch(output, "m)^first (?:[6-9]\d\d|1[01]\d\d) \d+ 240 160 1$"),
                "An available subclass API still permits native placement: " output)
    }
    Check(DllCall(functions["Block"], "Int", 1, "Int"), "No native show remains in flight")
    path := logPath ".blocked"
    RunWait '"' folder '\placement-fixture64.exe" "' path '" blocked' localHook
    Check(InStr(FileRead(path), "first 100 100"), "Workspace navigation blocks native placement")
    Check(DllCall(functions["Block"], "Int", 0, "Int"), "Release navigation guard")
    DllCall functions["Stop"]
    ProcessWaitClose host, 3
    Check(!ProcessExist(host), "x86 host unhooks and exits when controller stops")
    FileAppend "PASS: native x64/x86 CBT normal-window first WM_PAINT on destination, saved/default/visible creation, maximized restore bounds, old HWND, reshow, early/visible owner dialog, exclusions, destruction, workspace guard, blocked-show skip, application-crash recovery, hosts with/without a Common Controls v6 manifest, Run first-paint placement/DPI layout/reuse/restart/request expiry and host shutdown; simulated work areas; explicit fixture loading=" (localHook != "") "; Windows global injection/physical DPI behavior unverified`n", logPath, "UTF-8"
}
catch as err {
    failure := err.Message "`n" err.Stack
    if IsSet(functions) && functions.Has("Status") {
        for index in [0, 1, 2, 3, 4]
            failure .= "`nstatus[" index "]=" DllCall(functions["Status"], "UInt", index, "UInt")
    }
}
finally {
    if heartbeat
        SetTimer heartbeat, 0
    if library {
        if IsSet(functions) && functions.Has("Stop")
            DllCall functions["Stop"]
        DllCall "FreeLibrary", "Ptr", library
    }
    for pid in [host, existing, fixturePid] {
        if pid && ProcessExist(pid)
            ProcessClose pid
    }
}
if failure != "" {
    FileAppend "FAIL: " failure "`n", logPath, "UTF-8"
    ExitApp 1
}
ExitApp 0

Check(condition, message) {
    if !condition
        throw Error(message)
}
