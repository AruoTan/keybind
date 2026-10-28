; Operation sequence, verification, rollback and empty-desktop cleanup.
VDOrder(ids) {
    result := ""
    for id in ids
        result .= id "|"
    return result
}

class VDController {
    __New(api, windows, timeout := 1500, settle := 100, report := VDReport, log := VDLog) {
        this.Api := api
        this.Windows := windows
        this.Timeout := timeout
        this.Settle := settle
        this.Report := report
        this.Log := log
        this.Busy := false
    }

    Move(direction) {
        if direction != -1 && direction != 1
            throw ValueError("Direction must be -1 or 1")
        this.Log.Call("Operation begin; action=move; direction=" direction)
        if this.Busy
            return this.Result("move", direction, "busy")
        this.Busy := true
        source := "", target := "", created := "", group := 0
        moveAttempted := false, switched := false
        try {
            group := this.Windows.Capture()
            if !IsObject(group)
                return this.Result("move", direction, "no-window")
            api := this.Api
            order := api.Snapshot()
            source := api.Current()
            sourceIndex := this.Find(order, source)
            for token in group.Members {
                if !this.Windows.Valid(token)
                    return this.Result("move", direction, "no-window", source)
                if api.Pinned(token.Hwnd)
                    return this.Result("move", direction, "pinned", source)
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
            this.Route("move", source, target, order, created)
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
            return this.Result("move", direction, "moved", source, target)
        }
        catch as err {
            if moveAttempted && !switched
                this.Rollback(group, source, target)
            if created != "" && !switched
                this.ReclaimCreated(created, source)
            this.Report.Call(VDErrorText(err))
            return this.Result("move", direction, switched ? "moved-retained" : "failed", source, target)
        }
        finally {
            this.Busy := false
        }
    }

    ; Ctrl+Win switches without moving windows, including from an empty desktop.
    ; Extend at either boundary and collect only the confirmed-empty source.
    Switch(direction, focus := 0) {
        if direction != -1 && direction != 1
            throw ValueError("Direction must be -1 or 1")
        this.Log.Call("Operation begin; action=switch; direction=" direction)
        if this.Busy
            return this.Result("switch", direction, "busy")
        this.Busy := true
        source := "", target := "", created := ""
        switched := false, focused := false
        try {
            order := this.Api.Snapshot()
            source := this.Api.Current()
            index := this.Find(order, source) + direction
            this.CheckOrder(order)
            if index < 0 || index >= order.Length {
                created := this.Api.Create()
                order.Push(created)
                this.Await(() => VDOrder(this.Api.Snapshot()) = VDOrder(order))
                target := created
                if direction = -1 {
                    this.Api.Reorder(created, 0)
                    order.Pop()
                    order.InsertAt(1, created)
                    this.Await(() => VDOrder(this.Api.Snapshot()) = VDOrder(order))
                }
            } else
                target := order[index + 1]
            this.CheckOrder(order)
            if this.Api.Current() != source
                throw Error("Current desktop changed before switch")
            this.Route("switch", source, target, order, created)
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
            focused := true
            ; RDP may hide its fullscreen window after deactivation. A known
            ; source app still assigned there must survive a visibility scan.
            if !IsObject(focus) || !HasMethod(focus, "SourceOccupied")
                || !focus.SourceOccupied(this.Api, source)
                this.RemoveIfEmpty(source, target, order)
            else
                this.Log.Call("Source desktop retained: source application still assigned; source=" source
                    "; target=" target)
            return this.Result("switch", direction, "switched", source, target)
        }
        catch as err {
            if created != "" && !switched
                this.ReclaimCreated(created, source)
            this.Report.Call(VDErrorText(err))
            return this.Result("switch", direction,
                switched ? (focused ? "switched-retained" : "switched-unfocused") : "failed", source, target)
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

    Result(action, direction, result, source := "", target := "") {
        this.Log.Call("Operation result; action=" action "; direction=" direction "; result=" result
            "; source=" source "; target=" target)
        return result
    }

    Route(action, source, target, order, created) {
        this.Log.Call("Desktop route; action=" action "; source=" source
            "; source-index=" this.Find(order, source) "; target=" target
            "; target-index=" this.Find(order, target) "; desktop-count=" order.Length
            "; created=" created)
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
        this.LastOccupant := 0
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
                if location = desktop {
                    this.LastOccupant := token
                    return false
                }
            }
            catch as err {
                ; Windows can disappear during a shell query. Live windows with
                ; unknown ownership/pin state still prevent desktop removal.
                if !this.Windows.Valid(token)
                    continue
                ignoreFrame := false
                ; A failed classification must retain the original query error
                ; and fail closed, including when DWM state is unavailable.
                try ignoreFrame := this.Windows.UntrackedFrame(token, err)
                if ignoreFrame
                    continue
                if this.Windows.Valid(token)
                    throw Error("Source desktop occupancy check failed: " VDErrorText(err), ,
                        this.Windows.Describe(token))
            }
        }
        return true
    }

    RemoveIfEmpty(source, fallback, order) {
        this.CheckOrder(order)
        if source = fallback || order.Length <= 1
            return this.RetainSource(source, fallback, "last desktop or identical fallback")
        if this.Api.Current() != fallback
            return this.RetainSource(source, fallback, "current desktop changed before scan")
        if !this.Empty(source) {
            blocker := "unknown"
            try blocker := this.Windows.Describe(this.LastOccupant)
            return this.RetainSource(source, fallback, "occupied; " blocker)
        }
        if this.Settle
            Sleep this.Settle
        this.CheckOrder(order)
        if this.Api.Current() != fallback
            return this.RetainSource(source, fallback, "current desktop changed before final scan")
        if !this.Empty(source) {
            blocker := "unknown"
            try blocker := this.Windows.Describe(this.LastOccupant)
            return this.RetainSource(source, fallback, "occupied on final scan; " blocker)
        }
        this.CheckOrder(order)
        if this.Api.Current() != fallback
            return this.RetainSource(source, fallback, "current desktop changed before removal")
        this.Api.Remove(source, fallback)
        expected := order.Clone()
        expected.RemoveAt(this.Find(expected, source) + 1)
        this.Await(() => VDOrder(this.Api.Snapshot()) = VDOrder(expected))
        this.Log.Call("Source desktop removed; source=" source "; target=" fallback
            "; target-index=" this.Find(expected, fallback) "; desktop-count=" expected.Length)
        return true
    }

    RetainSource(source, fallback, reason) {
        this.Log.Call("Source desktop retained: " reason "; source=" source "; target=" fallback)
        return false
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
