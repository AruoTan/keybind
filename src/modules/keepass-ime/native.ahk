; Bounded IME control-message calls shared by the controller and Windows tests.

KeePassImeControl(ime, command, value := 0) {
  result := 0
  if !DllCall("SendMessageTimeout", "Ptr", ime, "UInt", 0x283,
    "UPtr", command, "Ptr", value, "UInt", 0x2, "UInt", 400,
    "UPtr*", &result, "Ptr")
    throw OSError()
  return result
}
