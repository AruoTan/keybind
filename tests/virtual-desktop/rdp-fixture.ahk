#Requires AutoHotkey v2.0
#SingleInstance Off
; Run with a copy of the interpreter named msrdc.exe to exercise actual
; process matching with a non-mstsc window class, not a fake boolean.
fixture := Gui(, "Keybind RDP recognition fixture")
fixture.AddText(, "RDP process recognition test")
fixture.Show("w360 h100")
Persistent
