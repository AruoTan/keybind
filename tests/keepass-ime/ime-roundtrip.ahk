#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%/../../src/modules/keepass-ime.ahk
testLog := A_Args.Length ? A_Args[1] : A_Temp "\keybind-ime-test.log"
try FileDelete testLog
previous := WinExist("A")
KeePassImeInit()
fixture := Gui(, "KeePass IME bridge test (no credentials)")
testEdit := fixture.AddEdit("w360", "")
fixture.Show("w400 h90")
testEdit.Focus()
Sleep 200
ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", testEdit.Hwnd, "Ptr")
initialOpen := 0
initialConversion := 0
captured := false
exitCode := 0
try {
    if !ime
        throw Error("No IME window for test testEdit control")
    initialOpen := KeePassImeControl(ime, 5)
    initialConversion := KeePassImeControl(ime, 1)
    captured := true
    for originalOpen in [0, 1] {
        KeePassImeControl ime, 6, originalOpen
        if KeePassImeControl(ime, 5) != originalOpen
            throw Error("IME does not support setting open state " originalOpen)
        originalConversion := KeePassImeControl(ime, 1)
        if !KeePassImeBegin(fixture.Hwnd)
            throw Error("Begin failed for state " originalOpen)
        if KeePassImeControl(ime, 5) != 0
            throw Error("IME remained open during auto-type")
        if KeePassImeBegin(fixture.Hwnd)
            throw Error("Duplicate begin should be rejected")
        if !KeePassImeEnglish(fixture.Hwnd)
            throw Error("Reassert English failed")
        if !KeePassImeRestore(fixture.Hwnd)
            throw Error("Restore failed")
        if KeePassImeControl(ime, 5) != originalOpen
            throw Error("Original open state was not restored")
        if originalOpen && KeePassImeControl(ime, 1) != originalConversion
            throw Error("Original conversion flags were not restored")
        FileAppend "PASS: state " originalOpen " -> English -> original state`n", testLog
    }
    if !KeePassImeRestore(fixture.Hwnd)
        throw Error("Repeated restore should be harmless")
    if KeePassImeBegin(0)
        throw Error("Invalid target should be rejected")
    FileAppend "PASS: repeated restore and invalid target`n", testLog
}
catch as err {
    FileAppend "FAIL: " err.Message " (line " err.Line ")`n", testLog
    exitCode := 1
}
finally {
    try KeePassImeRestore()
    if captured {
        try KeePassImeControl ime, 6, initialOpen
        try KeePassImeControl ime, 2, initialConversion
    }
    fixture.Destroy()
    if previous && WinExist(previous)
        try WinActivate previous
}
ExitApp exitCode
