; General keyboard shortcuts.
; Leave other Win shortcuts to the remote session while an RDP client has focus.
#HotIf !RemoteDesktopActive()
#^SPACE:: {
    WinSetAlwaysOnTop -1, "A"
}
#HotIf
