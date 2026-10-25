; Mouse shortcuts and the physical Snipaste gesture.
MouseInit() {
    global XButton2Hold
    InstallKeybdHook()
    InstallMouseHook()
    XButton2Hold := {Down: false, Used: false, WinOwned: false}
    OnExit EndXButton2Hold
}

XButton1:: SendInput "{Ctrl down}v{Ctrl up}"

EndXButton2Hold(*) {
    global XButton2Hold
    Critical

    if !XButton2Hold.Down
        return

    XButton2Hold.Down := false
    SetTimer WatchXButton2Hold, 0
    SetKeyDelay -1, -1
    ; Do not release a Win key which the user is physically holding.
    ; vkE8 masks the Start menu, including after a standalone copy press.
    if XButton2Hold.WinOwned && !GetKeyState("LWin", "P")
        SendEvent "{Blind}{vkE8}{LWin up}"
    XButton2Hold.WinOwned := false
}

WatchXButton2Hold() {
    global XButton2Hold
    Critical

    if !XButton2Hold.Down
        return
    if !GetKeyState("XButton2", "P") {
        EndXButton2Hold()
        return
    }
    ; Also consume copy if another hook prevented our click hotkey from firing
    ; but the physical mouse-down state is still available to AutoHotkey.
    if GetKeyState("LButton", "P")
        XButton2Hold.Used := true
}

; Arm Win at side-button down, before the subsequent physical left click.
; Keep it held until side-button up, allowing repeated drags during one hold.
*XButton2:: {
    global XButton2Hold
    Critical

    if XButton2Hold.Down
        return
    XButton2Hold.Down := true
    XButton2Hold.Used := GetKeyState("LButton", "P")
    XButton2Hold.WinOwned := !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P")
    SetKeyDelay -1, -1
    if XButton2Hold.WinOwned
        SendEvent "{Blind}{LWin down}"
    SetTimer WatchXButton2Hold, 10
}

*XButton2 Up:: {
    global XButton2Hold
    Critical

    if !XButton2Hold.Down
        return
    copyOnRelease := !XButton2Hold.Used
    EndXButton2Hold()
    if copyOnRelease
        SendInput "{Ctrl down}c{Ctrl up}"
}

; Observe clicks without suppressing or recreating either mouse event.
; Keep this unconditional so a delayed callback still consumes the copy action.
~*LButton:: {
    global XButton2Hold
    Critical
    if XButton2Hold.Down || GetKeyState("XButton2", "P")
        XButton2Hold.Used := true
}

#HotIf WinActive("ahk_class CabinetWClass")
MButton:: {
    Send "!{Up}"
}
#HotIf
