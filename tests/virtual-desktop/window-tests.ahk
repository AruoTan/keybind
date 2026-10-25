#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%/../../../src/modules/virtual-desktop/virtual-desktop.ahk

logPath := A_Args[1]
skipDwm := A_Args.Length >= 2 && A_Args[2] = "--skip-dwm"
windows := VDWindows(), fixtures := []
try {
    main := Gui(, "Keybind window classification test"), fixtures.Push(main)
    main.Show("w300 h100")
    token := windows.Token(main.Hwnd)
    description := windows.Describe(token)
    Check(InStr(description, Format("HWND 0x{:X}", main.Hwnd))
        && InStr(description, "class AutoHotkeyGUI") && !InStr(description, "Keybind window"),
        "Window diagnostics must identify the class/handle without logging its title")
    Check(windows.Ordinary(main.Hwnd), "Normal GUI must count as application")
    main.Minimize()
    Check(windows.Ordinary(main.Hwnd), "Minimized GUI must count as application")
    main.Restore()
    ; DWM shell cloak (2) must not make an ordinary application disappear from
    ; occupancy checks. An application cloak is sufficient to exercise that rule.
    if !skipDwm {
        cloak := 1
        hr := DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", main.Hwnd, "UInt", 13,
            "Int*", &cloak, "UInt", 4, "Int")
        if hr < 0
            throw Error("Cannot cloak fixture for classification test")
        Check(windows.Ordinary(main.Hwnd), "Cloaked GUI must count as application")
        cloak := 0
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", main.Hwnd, "UInt", 13,
            "Int*", &cloak, "UInt", 4, "Int")
    }
    main.Hide()
    Check(!windows.Ordinary(main.Hwnd), "Truly hidden background GUI must be ignored")
    main.Show()
    tool := Gui("+ToolWindow", "Keybind tool fixture"), fixtures.Push(tool)
    tool.Show("w200 h80")
    Check(!windows.Ordinary(tool.Hwnd), "Tool GUI must be ignored")
    noactivate := Gui("+E0x08000000", "Keybind noactivate fixture"), fixtures.Push(noactivate)
    noactivate.Show("NoActivate w200 h80")
    Check(!windows.Ordinary(noactivate.Hwnd), "Noactivate GUI must be ignored")
    ownedTool := Gui("+ToolWindow +Owner" main.Hwnd, "Keybind owned tool fixture"), fixtures.Push(ownedTool)
    ownedTool.Show("w200 h80")
    WinActivate "ahk_id " ownedTool.Hwnd
    Check(!!WinWaitActive("ahk_id " ownedTool.Hwnd, , 1), "Owned tool fixture must get focus")
    Check(!IsObject(windows.Capture()), "Active owned tool must not move its owner")
    ownedTool.Hide()
    dialog := Gui("+Owner" main.Hwnd, "Keybind owned dialog fixture"), fixtures.Push(dialog)
    dialog.Show("w200 h80")
    WinActivate "ahk_id " dialog.Hwnd
    Check(!!WinWaitActive("ahk_id " dialog.Hwnd, , 1), "Fixture must get foreground focus")
    group := windows.Capture()
    Check(IsObject(group) && group.Root.Hwnd = main.Hwnd && group.Active.Hwnd = dialog.Hwnd,
        "Owned dialog must capture its root and original focus")
    Check(group.Members.Length = 2, "Only owner group belongs to the move")
    Check(windows.System(DllCall("GetDesktopWindow", "Ptr")), "Desktop must be excluded")
    main.Destroy()
    Check(!windows.Valid(token), "Destroyed window token must be rejected")
    coverage := skipDwm ? " (DWM cloak test skipped)" : " including DWM cloak"
    FileAppend "PASS: real window classification, minimized, tool and owner-group fixtures" coverage "`n", logPath, "UTF-8"
}
catch as err {
    FileAppend "FAIL: " err.Message "`nExtra: " err.Extra "`n" err.Stack "`n", logPath, "UTF-8"
    ExitApp 1
}
finally {
    for fixture in fixtures {
        try fixture.Destroy()
    }
}
ExitApp 0

Check(condition, message) {
    if !condition
        throw Error(message)
}
