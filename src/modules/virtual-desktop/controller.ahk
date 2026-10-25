; Operation sequence, verification, rollback and empty-desktop cleanup.
VDOrder(ids) {
    result := ""
    for id in ids
        result .= id "|"
    return result
}

class VDController {
    __New(api, windows, timeout := 1500, settle := 100, report := VDReport) {
        this.Api := api
        this.Windows := windows
        this.Timeout := timeout
        this.Settle := settle
        this.Report := report
        this.Busy := false
    }

    Move(direction) {
        if direction != -1 && direction != 1
            throw ValueError("Direction must be -1 or 1")
        if this.Busy
            return "busy"
        this.Busy := true
        source := "", target := "", created := "", group := 0
        moveAttempted := false, switched := false
        try {
            group := this.Windows.Capture()
            if !IsObject(group)
                return "no-window"
            api := this.Api
            order := api.Snapshot()
            source := api.Current()
            sourceIndex := this.Find(order, source)
            for token in group.Members {
                if !this.Windows.Valid(token)
                    return "no-window"
                if api.Pinned(token.Hwnd)
                    return "pinned"
                if api.WindowId(token.Hwnd) != source
                    throw Error("Active window group is not on the current desktop")
            }
            this.CheckOrder(order)
            index := sourceIndex + direction
            if index < 0 || index >= order.Length {
                created := api.Create()
                order.Push(created)
                this.Await(() => VDOrder(api.Snapshot()) = VDOrder(order))
                target := created
                if direction = -1 {
                    api.Reorder(created, 0)
                    order.Pop()
                    order.InsertAt(1, created)
                    this.Await(() => VDOrder(api.Snapshot()) = VDOrder(order))
                }
            } else
                target := order[index + 1]

            this.CheckOrder(order)
            if api.Current() != source || !this.Windows.StillActive(group)
                throw Error("Foreground window or current desktop changed")
            for token in group.Members {
                this.CheckOrder(order)
                if !this.Windows.Valid(token) || api.Pinned(token.Hwnd)
                    throw Error("Window group changed before move")
                desktop := api.WindowId(token.Hwnd)
                if desktop = target
                    continue ; Windows may move owned dialogs with the root.
                if desktop != source
                    throw Error("Window moved externally before move")
                ; A failed native call may have had a partial effect.
                moveAttempted := true
                api.MoveWindow(token.Hwnd, target)
            }
            this.Await(() => this.GroupOn(group, target))
            this.CheckOrder(order)
            if api.Current() != source
                throw Error("Current desktop changed during move")
            api.Go(target)
            this.Await(() => api.Current() = target)
            this.Await(() => this.GroupOn(group, target))
            switched := true
            if !this.Windows.Focus(group)
                throw Error("Window moved, but focus could not be restored; source retained")
            this.RemoveIfEmpty(source, target, order)
            return "moved"
        }
        catch as err {
            if moveAttempted && !switched
                this.Rollback(group, source, target)
            if created != "" && !switched
                this.ReclaimCreated(created, source)
            this.Report.Call(VDErrorText(err))
            return switched ? "moved-retained" : "failed"
        }
        finally {
            this.Busy := false
        }
    }

    ; Used by the local RDP shortcut. Never move windows, create desktops or
    ; collect empty desktops for an ordinary Ctrl+Win desktop switch.
    Switch(direction, focus := 0) {
        if direction != -1 && direction != 1
            throw ValueError("Direction must be -1 or 1")
        if this.Busy
            return "busy"
        this.Busy := true
        switched := false
        try {
            order := this.Api.Snapshot()
            source := this.Api.Current()
            index := this.Find(order, source) + direction
            if index < 0 || index >= order.Length
                return "boundary"
            target := order[index + 1]
            this.CheckOrder(order)
            if this.Api.Current() != source
                throw Error("Current desktop changed before switch")
            if IsObject(focus) {
                focus.Before(this.Api, source, target)
                this.CheckOrder(order)
                if this.Api.Current() != source
                    throw Error("Current desktop changed during focus handoff")
            }
            this.Api.Go(target)
            this.Await(() => this.Api.Current() = target)
            switched := true
            if IsObject(focus) && !focus.After(this.Api, source, target)
                throw Error("Desktop switched, but local keyboard focus could not be restored")
            return "switched"
        }
        catch as err {
            this.Report.Call(VDErrorText(err))
            return switched ? "switched-unfocused" : "failed"
        }
        finally {
            if IsObject(focus) {
                try focus.Close()
                catch as err
                    this.Report.Call("Focus handoff cleanup failed: " VDErrorText(err))
            }
            this.Busy := false
        }
    }

    Find(order, id) {
        for index, candidate in order {
            if candidate = id
                return index - 1
        }
        throw Error("Desktop no longer exists")
    }

    CheckOrder(order) {
        if VDOrder(this.Api.Snapshot()) != VDOrder(order)
            throw Error("Desktop order changed externally; operation stopped")
    }

    Await(predicate) {
        started := A_TickCount
        loop {
            if predicate.Call()
                return
            if A_TickCount - started >= this.Timeout
                throw Error("Timed out waiting for Windows virtual desktop state")
            ; Do not use Critical across waits: KeePass and mouse hooks must run.
            Sleep 20
        }
    }

    GroupOn(group, desktop) {
        if !this.Windows.Valid(group.Root)
            throw Error("Main window closed during operation")
        for token in group.Members {
            if this.Windows.Valid(token) && this.Api.WindowId(token.Hwnd) != desktop
                return false
        }
        return true
    }

    Empty(desktop) {
        for token in this.Windows.Applications() {
            if !this.Windows.Valid(token)
                continue
            try {
                ; Only an explicit successful GUID_NULL may be ignored. A DLL
                ; zero on its own cannot distinguish unassigned from query failure.
                location := this.Api.WindowId(token.Hwnd, true)
                if !this.Windows.Valid(token)
                    continue
                if location = "" || this.Api.Pinned(token.Hwnd)
                    continue
                if location = desktop
                    return false
            }
            catch as err {
                ; Windows can disappear during a shell query. Live windows with
                ; unknown ownership/pin state still prevent desktop removal.
                if this.Windows.Valid(token)
                    throw Error("Source desktop occupancy check failed: " VDErrorText(err), ,
                        this.Windows.Describe(token))
            }
        }
        return true
    }

    RemoveIfEmpty(source, fallback, order) {
        this.CheckOrder(order)
        if source = fallback || order.Length <= 1 || this.Api.Current() != fallback
            return false
        if !this.Empty(source)
            return false
        if this.Settle
            Sleep this.Settle
        this.CheckOrder(order)
        if this.Api.Current() != fallback || !this.Empty(source)
            return false
        this.CheckOrder(order)
        this.Api.Remove(source, fallback)
        expected := order.Clone()
        expected.RemoveAt(this.Find(expected, source) + 1)
        this.Await(() => VDOrder(this.Api.Snapshot()) = VDOrder(expected))
        return true
    }

    Rollback(group, source, target) {
        try {
            this.Api.Index(source)
            current := this.Api.Current()
            if current != source && current != target
                throw Error("Rollback skipped after an external desktop switch")
            for token in group.Members {
                if !this.Windows.Valid(token)
                    continue
                if this.Api.Pinned(token.Hwnd)
                    throw Error("Rollback stopped: a window became pinned")
                desktop := this.Api.WindowId(token.Hwnd)
                if desktop = target
                    this.Api.MoveWindow(token.Hwnd, source)
                else if desktop != source
                    throw Error("Rollback stopped: a window moved externally")
            }
            this.Await(() => this.GroupOn(group, source))
            if this.Api.Current() = target {
                this.Api.Go(source)
                this.Await(() => this.Api.Current() = source)
            }
            this.Windows.Focus(group)
        }
        catch as err {
            this.Report.Call("Rollback incomplete: " VDErrorText(err))
        }
    }

    ReclaimCreated(created, source) {
        try {
            if this.Api.Current() != source
                return
            this.RemoveIfEmpty(created, source, this.Api.Snapshot())
        }
        catch as err {
            this.Report.Call("New desktop retained: " VDErrorText(err))
        }
    }
}
