; Physical chord recognition is independent of AHK's logical modifier state.
class RDPKeyFilter {
    __New() {
        this.Down := Map()
        this.Owned := Map()
        this.Sequence := 0
        this.SwitchChain := false
    }

    Any(keys*) {
        for key in keys {
            if this.Down.Has(key)
                return true
        }
        return false
    }

    ModifierState() {
        result := ""
        for vk, sequence in this.Down {
            if RDPModifierTrace.Names.Has(vk)
                result .= (result = "" ? "" : ",") RDPModifierTrace.Names[vk] "#" sequence
        }
        return result = "" ? "none" : result
    }

    ResetInactive(snapshot := 0) {
        removed := 0
        for vk in this.Down.Clone() {
            if !this.Owned.Has(vk) && (!IsObject(snapshot)
                || (snapshot.Has(vk) && snapshot[vk] = this.Down[vk])) {
                this.Down.Delete(vk)
                removed += 1
            }
        }
        return removed ; Owned arrows still require their real key-up.
    }

    Event(vk, up, injected, active, localSwitch := false) {
        if injected
            return 0
        repeated := this.Down.Has(vk)
        if up {
            if repeated
                this.Down.Delete(vk)
        } else
            this.Down[vk] := ++this.Sequence
        if up && (!this.Any(0x5B, 0x5C) || !this.Any(0x11, 0xA2, 0xA3))
            this.SwitchChain := false
        if this.Owned.Has(vk) {
            if up
                this.Owned.Delete(vk)
            return -1 ; Swallow repeat and key-up, even after focus changes.
        }
        if up || repeated || (!active && !localSwitch) || (vk != 0x25 && vk != 0x27)
            return 0
        win := this.Any(0x5B, 0x5C)
        ctrl := this.Any(0x11, 0xA2, 0xA3)
        shift := this.Any(0x10, 0xA0, 0xA1)
        alt := this.Any(0x12, 0xA4, 0xA5)
        if !win || alt || ctrl = shift
            return 0
        if shift && !active
            return 0 ; Local Win+Shift is still handled by its existing hotkey.
        this.Owned[vk] := true
        if ctrl && localSwitch
            this.SwitchChain := true
        ; 1/2 = switch left/right; 3/4 = move left/right.
        return (shift ? 3 : 1) + (vk = 0x27)
    }
}

; A bounded history of modifier transitions only. Ordinary keys never enter
; this buffer. It is written only when a Win+arrow chord is rejected.
class RDPModifierTrace {
    static Names := Map(0x10, "Shift", 0x11, "Ctrl", 0x12, "Alt",
        0x5B, "LWin", 0x5C, "RWin", 0xA0, "LShift", 0xA1, "RShift",
        0xA2, "LCtrl", 0xA3, "RCtrl", 0xA4, "LAlt", 0xA5, "RAlt")

    __New() {
        this.Events := []
    }

    Record(vk, up, flags, scan, active, now) {
        if !RDPModifierTrace.Names.Has(vk)
            return
        this.Events.Push("tick=" now " " RDPModifierTrace.Names[vk] (up ? " up" : " down")
            . Format("; vk=0x{:X}; scan=0x{:X}; flags=0x{:X}; active={}", vk, scan, flags, active))
        if this.Events.Length > 32
            this.Events.RemoveAt(1)
    }
}

class RDPKeyboardHook {
    __New() {
        this.Handle := 0
        this.Handles := []
        this.Window := 0
        this.Filter := RDPKeyFilter()
        this.Requests := Map()
        this.Working := false
        this.Serial := 0
        this.Message := 0x804B
        this.Fault := ""
        this.Probe := ""
        this.Trace := RDPModifierTrace()
        this.Rejected := []
        this.AwaySince := -1
        this.AwayDown := Map()
        this.AwayCleaned := false
        this.Address := CallbackCreate(this.Proc.Bind(this), , 3)
    }

    Reinstall() {
        ; Install first so reclaiming priority has no unhooked input gap.
        ; Preserve the filter: refreshing during a held chord cannot re-arm it.
        replacement := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", this.Address,
            "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
        if !replacement
            throw Error("Cannot install RDP keyboard hook (Win32 " A_LastError ")")
        previous := this.Handle
        this.Handle := replacement
        this.Handles.Push(replacement)
        if previous {
            if !DllCall("UnhookWindowsHookEx", "Ptr", previous, "Int") && A_LastError != 1404
                throw Error("Cannot remove RDP keyboard hook (Win32 " A_LastError ")")
            for index, handle in this.Handles {
                if handle = previous {
                    this.Handles.RemoveAt(index)
                    break
                }
            }
        }
    }

    Close() {
        while this.Handles.Length {
            if !DllCall("UnhookWindowsHookEx", "Ptr", this.Handles[1], "Int") && A_LastError != 1404
                return ; Do not free a callback that Windows could still call.
            this.Handles.RemoveAt(1)
        }
        this.Handle := 0
        if this.Address {
            CallbackFree this.Address
            this.Address := 0
        }
        this.Requests.Clear()
    }

    ObserveWindow(window, now, nativeKeysDown) {
        this.Window := window
        if window || this.Working || this.Filter.SwitchChain {
            this.AwaySince := -1
            this.AwayCleaned := false
            return
        }
        if this.AwaySince < 0 {
            this.AwaySince := now
            this.AwayDown := this.Filter.Down.Clone()
        }
        elapsed := now - this.AwaySince
        ; Native state can itself stay stuck after RDP consumes key-up. Bound
        ; that wait too; clear only records that predate leaving the session.
        if !this.AwayCleaned && elapsed >= 300 && (!nativeKeysDown || elapsed >= 800) {
            before := this.Filter.ModifierState()
            removed := this.Filter.ResetInactive(this.AwayDown)
            this.AwayCleaned := true
            if removed
                RemoteDesktopLog("Cleared stale key state outside session; count=" removed
                    "; native-held=" nativeKeysDown "; before=" before
                    "; after=" this.Filter.ModifierState())
        }
    }

    Proc(code, message, data) {
        code := code << 32 >> 32
        if code >= 0 {
            try {
                vk := NumGet(data, 0, "UInt")
                flags := NumGet(data, 8, "UInt")
                injected := flags & 0x10
                up := message = 0x101 || message = 0x105
                foreground := DllCall("GetForegroundWindow", "Ptr")
                active := this.Window && foreground = this.Window
                firstDown := !up && !this.Filter.Down.Has(vk)
                this.Trace.Record(vk, up, flags, NumGet(data, 4, "UInt"), active, A_TickCount)
                action := this.Filter.Event(vk, up, injected, active, true)
                if (active || action > 0) && firstDown && (vk = 0x25 || vk = 0x27) {
                    win := this.Filter.Any(0x5B, 0x5C)
                    if win {
                        ; Defer this diagnostic to the timer. Record only Win
                        ; arrow modifier bits, never text or ordinary keys.
                        this.Probe := "Arrow " (vk = 0x25 ? "Left" : "Right")
                            . "; W=" win "; C=" this.Filter.Any(0x11, 0xA2, 0xA3)
                            . "; S=" this.Filter.Any(0x10, 0xA0, 0xA1)
                            . "; A=" this.Filter.Any(0x12, 0xA4, 0xA5)
                            . "; injected=" (!!injected) "; action=" action
                        if !action && this.Rejected.Length < 4 {
                            this.Rejected.Push({Summary: this.Probe, Tick: A_TickCount,
                                State: this.Filter.ModifierState(), Events: this.Trace.Events.Clone()})
                        }
                    }
                }
                if action {
                    if action > 0 {
                        ; Mask an otherwise standalone Win release in the RDP
                        ; session. Injected mask keys are never treated as chords.
                        DllCall("keybd_event", "UChar", 0xE8, "UChar", 0, "UInt", 0, "UPtr", 0)
                        DllCall("keybd_event", "UChar", 0xE8, "UChar", 0, "UInt", 2, "UPtr", 0)
                        if !this.Working && this.Requests.Count = 0 {
                            serial := ++this.Serial
                            this.Requests[serial] := {Action: action, Window: foreground}
                            if !DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", this.Message,
                                "UPtr", serial, "Ptr", 0, "Int") {
                                this.Requests.Delete(serial)
                                this.Fault := "Cannot queue RDP shortcut"
                            }
                        }
                    }
                    return 1
                }
            }
            catch as err {
                this.Fault := err.Message
            }
        }
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", code,
            "UPtr", message, "Ptr", data, "Ptr")
    }
}
