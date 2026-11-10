#Requires AutoHotkey v2.0
#SingleInstance Off
main := Gui(, "Placement child primary")
main.AddEdit("w200", "placement fixture")
main.Show("x100 y100 w260 h150")
dialog := Gui("+Owner" main.Hwnd, "Placement child dialog")
dialog.AddText(, "Owned dialog")
dialog.Show("x120 y140 w240 h100")
SetTimer () => ExitApp(), -15000
