; KeePass bridge protocol v1: 1=begin, 2=ensure English, 3=restore.
; Only window handles are exchanged, never entry contents or keystrokes.
#Include %A_LineFile%/../controller.ahk
#Include %A_LineFile%/../native.ahk

KeePassImeInit() {
  global KeePassImeWindow, KeePassImeState
  KeePassImeState := 0
  KeePassImeWindow := Gui("+ToolWindow -Caption", "Keybind.KeePassImeBridge.v1")
  message := DllCall("RegisterWindowMessage", "Str", "Keybind.KeePassImeBridge.v1", "UInt")
  if !message
    throw OSError()
  OnMessage message, KeePassImeMessage
  OnExit KeePassImeExit
}

KeePassImeMessage(action, target, *) {
  Critical
  try {
    switch action {
      case 1: return KeePassImeBegin(target)
      case 2: return KeePassImeEnglish(target)
      case 3: return KeePassImeRestore(target)
    }
  }
  catch {
    ; The plugin aborts auto-type if the handshake fails.
    return 0
  }
  return 0
}

KeePassImeExit(*) {
  try KeePassImeRestore()
}
