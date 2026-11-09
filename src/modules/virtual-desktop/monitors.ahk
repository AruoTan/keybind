; Native desktops store inactive windows; the visible native desktop never
; changes during a per-monitor switch. No app is hidden with ShowWindow.
class VDMonitorApi {
    __New(native, windows, monitors := 0) {
        this.Native := native, this.Windows := windows
        this.Monitors := IsObject(monitors) ? monitors : VDMonitors()
        this.Serial := 0, this.Host := "", this.Parking := ""
        this.Views := Map(), this.Groups := Map(), this.Selected := ""
        this.Topology := "", this.Faulted := false
    }

    Recover() {
        ; RemoveDesktop transfers every remaining window to the fallback,
        ; including hidden dialogs and apps that cannot be classified.
        ids := this.Native.Snapshot()
        for id in ids {
            name := this.Native.Name(id)
            if !RegExMatch(name, "^Keybind storage v1 (\{[0-9A-Fa-f-]{36}\})$", &match)
                continue
            this.Release(id, match[1])
        }
    }

    Reset() {
        if this.Parking != ""
            this.Release(this.Parking, this.Host)
        this.Host := "", this.Parking := "", this.Topology := ""
        this.Views.Clear(), this.Groups.Clear(), this.Selected := ""
        this.Faulted := false
    }

    Release(id, fallback) {
        ids := this.Native.Snapshot()
        if !this.Contains(ids, id)
            return
        if !this.Contains(ids, fallback) || fallback = id {
            fallback := this.Native.Current()
            if fallback = id {
                for candidate in ids {
                    if candidate != id {
                        fallback := candidate
                        break
                    }
                }
            }
        }
        if fallback = id {
            ; The user may have closed every ordinary native desktop. Keep
            ; this last desktop and its windows, dropping only our marker.
            this.Native.Name(id, "Desktop 1")
            if this.Native.Name(id) != "Desktop 1"
                throw Error("Last storage desktop recovery was not confirmed")
        } else {
            this.Native.Remove(id, fallback)
            if this.Contains(this.Native.Snapshot(), id)
                throw Error("Storage desktop removal was not confirmed")
        }
        VDLog("Monitor storage recovered; source=" id "; fallback=" fallback)
    }

    Prepare() {
        topology := this.Monitors.Signature()
        if this.Host != "" && (this.Faulted || this.Native.Current() != this.Host
            || topology != this.Topology || (this.Parking != ""
                && !this.Contains(this.Native.Snapshot(), this.Parking)))
            this.Reset()
        if this.Monitors.Count() < 2
            return false
        if this.Host = ""
            this.Host := this.Native.Current(), this.Topology := topology
        this.Selected := this.Monitors.Pointer()
        this.View(this.Selected)
        this.Sync()
        return true
    }

    View(device) {
        if !this.Views.Has(device) {
            id := "workspace-" (++this.Serial)
            this.Views[device] := {Order: [id], Current: id}
        }
        return this.Views[device]
    }

    Sync() {
        this.CheckHost()
        seen := Map()
        ; Include newly opened dialogs and independent windows, preserving
        ; remembered groups when fullscreen RDP hides itself on deactivation.
        for token in this.Windows.Applications() {
            root := this.Windows.Owner(token.Hwnd, this.Groups)
            if seen.Has(root)
                continue
            group := this.Windows.Group(token.Hwnd, this.Groups)
            if !IsObject(group)
                continue
            seen[root] := true
            device := this.Monitors.Window(root)
            if device != this.Selected && (!this.Groups.Has(root)
                || this.Groups[root].Device != this.Selected)
                continue
            ; A successful GUID_NULL has no workspace; query failures still stop preparation.
            try location := this.Native.WindowId(root, true)
            catch as err {
                if this.Windows.UntrackedFrame(group.Root, err)
                    continue
                throw err
            }
            if location = "" || (location != this.Host && location != this.Parking)
                continue
            if !this.Groups.Has(root) {
                if location = this.Parking {
                    this.Faulted := true
                    throw Error("Untracked window entered monitor storage; recovery required")
                }
                this.Groups[root] := {Group: group, Device: device, Desktop: this.View(device).Current}
            } else {
                record := this.Groups[root]
                if !this.Windows.Valid(record.Group.Root) {
                    if location = this.Parking {
                        this.Faulted := true
                        throw Error("Stored window identity changed; recovery required")
                    }
                    this.Groups.Delete(root)
                    if location = this.Host
                        this.Groups[root] := {Group: group, Device: device, Desktop: this.View(device).Current}
                    continue
                }
                record.Group := group
                ; Dragging a visible window to another screen adopts that
                ; screen's current workspace, without moving other windows.
                if location = this.Host && (device != record.Device
                    || record.Desktop != this.View(record.Device).Current)
                    record.Device := device, record.Desktop := this.View(device).Current
                ; A window pinned while parked can later be unpinned while
                ; its logical workspace is visible. Bring it back without Go.
                if location = this.Parking && record.Device = this.Selected
                    && record.Desktop = this.Current() && !this.Pinned(root)
                    this.MoveWindow(root, record.Desktop)
            }
        }
        stale := []
        for root, record in this.Groups {
            if !this.Windows.Valid(record.Group.Root) {
                stale.Push(root)
                continue
            }
            if record.Device != this.Selected
                continue
            try location := this.Native.WindowId(root, true)
            catch as err {
                if this.Windows.UntrackedFrame(record.Group.Root, err) {
                    stale.Push(root)
                    continue
                }
                throw err
            }
            if location = "" || (location != this.Host && location != this.Parking)
                stale.Push(root)
        }
        for root in stale
            this.Groups.Delete(root)
    }

    CheckHost() {
        if this.Native.Current() != this.Host || this.Monitors.Signature() != this.Topology
            throw Error("Native desktop or monitor layout changed; operation stopped")
    }

    Snapshot() {
        this.CheckHost()
        return this.View(this.Selected).Order.Clone()
    }
    Current() {
        this.CheckHost()
        return this.View(this.Selected).Current
    }
    Index(id) {
        for index, candidate in this.Snapshot() {
            if candidate = id
                return index - 1
        }
        throw Error("Monitor workspace no longer exists")
    }
    Create() {
        id := "workspace-" (++this.Serial)
        this.View(this.Selected).Order.Push(id)
        return id
    }
    Reorder(id, index) {
        order := this.View(this.Selected).Order
        order.RemoveAt(this.Index(id) + 1)
        order.InsertAt(index + 1, id)
    }
    Pinned(hwnd) => this.Native.Pinned(hwnd)

    WindowId(hwnd, allowUnassigned := false) {
        root := this.Windows.Owner(hwnd, this.Groups)
        if this.Groups.Has(root) ? this.Groups[root].Device != this.Selected
            : this.Monitors.Window(root) != this.Selected
            return ""
        location := this.Native.WindowId(hwnd, allowUnassigned)
        if location = ""
            return ""
        if this.Groups.Has(root) {
            record := this.Groups[root]
            if this.Windows.Valid(record.Group.Root)
                && (location = this.Host || location = this.Parking)
                return record.Device = this.Selected ? record.Desktop : ""
        }
        ; An untracked live window on this screen blocks empty-source cleanup.
        if location = this.Host && this.Monitors.Window(root) = this.Selected
            return this.Current()
        return ""
    }

    Storage() {
        this.CheckHost()
        if this.Parking = "" {
            id := this.Native.Create()
            try {
                this.Native.Name(id, "Keybind storage v1 " this.Host)
                if this.Native.Name(id) != "Keybind storage v1 " this.Host
                    throw Error("Storage recovery name was not confirmed")
                this.Parking := id
            }
            catch as err {
                try this.Native.Remove(id, this.Host)
                throw err
            }
        }
        this.Native.Index(this.Parking)
        return this.Parking
    }

    Transfer(record, target, changes) {
        ; Record every member before moving the root: Windows can propagate
        ; the root's move to its dialogs even if the call later reports failure.
        if !this.Windows.Valid(record.Group.Root)
            throw Error("Main window closed before monitor transfer")
        members := []
        for token in record.Group.Members {
            if !this.Windows.Valid(token)
                continue
            this.CheckHost()
            if this.Pinned(token.Hwnd)
                throw Error("Window group became pinned; operation stopped")
            from := this.Native.WindowId(token.Hwnd)
            if from != this.Host && from != this.Parking
                throw Error("Window moved to another native desktop")
            changes.Push({Token: token, From: from})
            members.Push(token)
        }
        for token in members {
            this.CheckHost()
            if this.Windows.Valid(token) && this.Native.WindowId(token.Hwnd) != target
                this.Native.MoveWindow(token.Hwnd, target)
        }
        for token in members
            this.AwaitWindow(token, target)
    }

    AwaitWindow(token, target) {
        started := A_TickCount
        while this.Windows.Valid(token) && this.Native.WindowId(token.Hwnd) != target {
            if A_TickCount - started >= 1500
                throw Error("Timed out transferring a monitor workspace window")
            Sleep 20
        }
    }

    Rollback(changes) {
        for change in changes {
            try {
                if this.Windows.Valid(change.Token) {
                    location := this.Native.WindowId(change.Token.Hwnd)
                    if location != change.From {
                        if location != this.Host && location != this.Parking
                            throw Error("Rollback stopped: window moved externally")
                        this.Native.MoveWindow(change.Token.Hwnd, change.From)
                    }
                    this.AwaitWindow(change.Token, change.From)
                }
            }
            catch as err {
                this.Faulted := true
                VDLog("Monitor transfer rollback failed: " VDErrorText(err))
            }
        }
    }

    MoveWindow(hwnd, id) {
        this.Index(id)
        root := this.Windows.Owner(hwnd, this.Groups)
        if !this.Groups.Has(root) || this.Groups[root].Device != this.Selected
            throw Error("Active window is not on the pointer's monitor")
        record := this.Groups[root], changes := []
        try {
            ; Carrying the foreground group only changes logical ownership:
            ; keep it on the visible native desktop to avoid deactivating RDP.
            target := id = this.Current() || this.Native.WindowId(root) = this.Host
                ? this.Host : this.Storage()
            this.Transfer(record, target, changes)
            record.Desktop := id
        }
        catch as err {
            this.Rollback(changes)
            throw err
        }
    }

    Go(id) {
        this.Index(id)
        source := this.Current(), changes := []
        try {
            for root, record in this.Groups {
                if record.Device = this.Selected && record.Desktop = source && !this.Pinned(root)
                    this.Transfer(record, this.Storage(), changes)
            }
            for root, record in this.Groups {
                if record.Device = this.Selected && record.Desktop = id && !this.Pinned(root)
                    this.Transfer(record, this.Host, changes)
            }
            this.CheckHost()
            this.View(this.Selected).Current := id
        }
        catch as err {
            this.Rollback(changes)
            throw err
        }
    }

    Remove(id, fallback) {
        if id = this.Current() || id = fallback || this.Snapshot().Length <= 1
            throw Error("Refusing to remove the current/last monitor workspace")
        this.Index(fallback)
        for root, record in this.Groups {
            if record.Device = this.Selected && record.Desktop = id && this.Windows.Valid(record.Group.Root) {
                if !this.Pinned(root)
                    throw Error("Monitor workspace is still occupied")
                record.Desktop := fallback
            }
        }
        this.View(this.Selected).Order.RemoveAt(this.Index(id) + 1)
    }

    Contains(ids, id) {
        for candidate in ids {
            if candidate = id
                return true
        }
        return false
    }
}

class VDMonitors {
    Count() => MonitorGetCount()
    Signature() {
        signature := ""
        loop MonitorGetCount() {
            MonitorGet A_Index, &left, &top, &right, &bottom
            signature .= MonitorGetName(A_Index) ":" left "," top "," right "," bottom "|"
        }
        return signature
    }
    Pointer() {
        wasCritical := A_IsCritical, previous := 0
        Critical "On"
        try {
            previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
            point := Buffer(8)
            if !DllCall("GetCursorPos", "Ptr", point, "Int")
                throw OSError(, , "Cannot locate pointer monitor")
            return this.Device(DllCall("MonitorFromPoint", "Int64", NumGet(point, 0, "Int64"),
                "UInt", 2, "Ptr"))
        }
        finally {
            if previous
                DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
            Critical wasCritical
        }
    }
    Window(hwnd) => this.Device(DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr"))
    Device(monitor) {
        info := Buffer(104, 0)
        NumPut "UInt", info.Size, info
        if !DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", info, "Int")
            throw OSError(, , "Cannot identify monitor")
        return StrGet(info.Ptr + 40, 32, "UTF-16")
    }
    Work(device) {
        loop MonitorGetCount() {
            if MonitorGetName(A_Index) = device {
                MonitorGetWorkArea A_Index, &left, &top, &right, &bottom
                return {Left: left, Top: top, Right: right, Bottom: bottom}
            }
        }
        throw Error("Selected monitor was disconnected")
    }
}
