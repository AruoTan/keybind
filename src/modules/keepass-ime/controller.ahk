; Save, switch and restore target IME state, including crash recovery.

KeePassImeBegin(target) {
  global KeePassImeState
  if KeePassImeState || !DllCall("IsWindow", "Ptr", target)
    return 0

  pid := 0
  thread := DllCall("GetWindowThreadProcessId", "Ptr", target, "UInt*", &pid, "UInt")
  ; GUITHREADINFO: cbSize, flags, hwndActive, hwndFocus, ...
  info := Buffer(8 + 6 * A_PtrSize + 16, 0)
  NumPut "UInt", info.Size, info
  focus := target
  if DllCall("GetGUIThreadInfo", "UInt", thread, "Ptr", info) {
    candidate := NumGet(info, 8 + A_PtrSize, "Ptr")
    if candidate && DllCall("GetAncestor", "Ptr", candidate, "UInt", 2, "Ptr")
      = DllCall("GetAncestor", "Ptr", target, "UInt", 2, "Ptr")
      focus := candidate
  }
  ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", focus, "Ptr")
  layout := DllCall("GetKeyboardLayout", "UInt", thread, "Ptr")
  ; A non-IME keyboard needs no switching. Do not guess for Chinese/Japanese/Korean.
  if !ime && ((layout & 0x3FF) = 4 || (layout & 0x3FF) = 17 || (layout & 0x3FF) = 18)
    return 0

  state := {target: target, pid: pid, thread: thread, ime: ime,
    open: 0, conversion: 0}
  if ime {
    state.open := KeePassImeControl(ime, 0x5)       ; IMC_GETOPENSTATUS
    state.conversion := KeePassImeControl(ime, 0x1) ; IMC_GETCONVERSIONMODE
  }
  ; Save before the first mutation so a failed switch can still be rolled back.
  KeePassImeState := state
  SetTimer KeePassImeWatch, 500
  return KeePassImeEnglish(target)
}

KeePassImeEnglish(target) {
  global KeePassImeState
  if !KeePassImeState || KeePassImeState.target != target
    return 0
  ime := KeePassImeState.ime
  if !ime
    return 1
  ; Closing the IME selects direct (English) input without changing keyboard layout.
  KeePassImeControl ime, 0x6, 0                    ; IMC_SETOPENSTATUS
  return KeePassImeControl(ime, 0x5) = 0
}

KeePassImeRestore(target := 0) {
  global KeePassImeState
  if !KeePassImeState
    return 1
  state := KeePassImeState
  if target && state.target != target
    return 0
  pid := 0
  thread := DllCall("GetWindowThreadProcessId", "Ptr", state.target, "UInt*", &pid, "UInt")
  if thread = state.thread && pid = state.pid && state.ime
    && DllCall("IsWindow", "Ptr", state.ime) {
    ; Restore to the original target, never whichever window is now active.
    KeePassImeControl state.ime, 0x6, state.open
    KeePassImeControl state.ime, 0x2, state.conversion
    if KeePassImeControl(state.ime, 0x5) != state.open
      return 0
    if state.open && KeePassImeControl(state.ime, 0x1) != state.conversion
      return 0
  }
  KeePassImeState := 0
  SetTimer KeePassImeWatch, 0
  return 1
}

KeePassImeWatch() {
  ; A crashed KeePass cannot send its final notification. No typing-duration timeout.
  if !ProcessExist("KeePass.exe")
    try KeePassImeRestore()
}
