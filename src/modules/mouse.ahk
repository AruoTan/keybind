; Mouse shortcuts.
XButton1:: SendInput "{Ctrl down}v{Ctrl up}"
XButton2:: SendInput "{Ctrl down}c{Ctrl up}"

#HotIf WinActive("ahk_class CabinetWClass")
MButton:: {
    Send "!{Up}"
}
#HotIf
