; General keyboard shortcuts.
; Leave other Win shortcuts to the remote session while an RDP client has focus.
#HotIf !RemoteDesktopActive()
#+s:: Send "{PrintScreen}"

#^SPACE:: {
    WinSetAlwaysOnTop -1, "A"
}
#HotIf
