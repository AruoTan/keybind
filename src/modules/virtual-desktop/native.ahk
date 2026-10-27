; VirtualDesktopAccessor exports and Windows x64 GUID ABI.
class VDWindowQueryError extends Error {
    __New(hwnd, hresult) {
        super.__New("GetWindowDesktopId query failed", -1,
            Format("HWND 0x{:X}; HRESULT 0x{:08X}", hwnd, hresult & 0xFFFFFFFF))
        this.Hwnd := hwnd
        this.HResult := hresult & 0xFFFFFFFF
    }
}

class VDNative {
    __New(path) {
        if A_PtrSize != 8
            throw Error("Virtual desktops require 64-bit AutoHotkey")
        this.Module := 0
        ; Full path, DLL directory and System32 only; never search the CWD.
        this.Module := DllCall("LoadLibraryExW", "Str", path, "Ptr", 0,
            "UInt", 0x100 | 0x800, "Ptr")
        if !this.Module
            throw Error("Cannot load VirtualDesktopAccessor.dll (Win32 " A_LastError ")")
        this.Procs := Map()
        for name in ["GetDesktopCount", "GetCurrentDesktopNumber", "GetDesktopIdByNumber",
            "GetDesktopNumberById", "GetWindowDesktopId", "IsPinnedWindow", "IsPinnedApp",
            "CreateDesktop", "MoveDesktop", "MoveWindowToDesktopNumber", "GoToDesktopNumber",
            "RemoveDesktop"] {
            address := DllCall("GetProcAddress", "Ptr", this.Module, "AStr", name, "Ptr")
            if !address
                throw Error("DLL is missing export: " name)
            this.Procs[name] := address
        }
    }

    __Delete() {
        if this.HasOwnProp("Module") && this.Module
            DllCall("FreeLibrary", "Ptr", this.Module)
    }

    Int(name, parameters*) {
        parameters.Push("Int")
        result := DllCall(this.Procs[name], parameters*)
        if result < 0
            throw Error("VirtualDesktopAccessor failed: " name)
        return result
    }

    Success(name, parameters*) {
        if this.Int(name, parameters*) != 1
            throw Error("Unexpected DLL result: " name)
    }

    GuidResult(name, argument, type := "Int", allowEmpty := false) {
        ; Windows x64 ABI: a 16-byte return struct uses a hidden first pointer.
        ; A GUID passed by value is likewise passed as a pointer to a temporary.
        storage := Buffer(31, 0)
        pointer := (storage.Ptr + 15) & ~15
        returned := DllCall(this.Procs[name], "Ptr", pointer, type, argument, "Ptr")
        if returned != pointer
            throw Error("Invalid GUID return ABI: " name)
        if !(NumGet(pointer, 0, "UInt64") | NumGet(pointer, 8, "UInt64")) {
            if allowEmpty
                return ""
            throw Error("No desktop GUID returned: " name)
        }
        return this.FormatGuid(pointer)
    }

    FormatGuid(pointer) {
        text := Buffer(78, 0)
        if !DllCall("ole32\StringFromGUID2", "Ptr", pointer, "Ptr", text, "Int", 39, "Int")
            throw Error("Cannot format desktop GUID")
        return StrGet(text, "UTF-16")
    }

    Id(index) => this.GuidResult("GetDesktopIdByNumber", index)
    WindowId(hwnd, allowUnassigned := false) {
        id := this.GuidResult("GetWindowDesktopId", hwnd, "Ptr", true)
        if id = "" {
            ; The DLL maps BOTH a failed HRESULT and a successful GUID_NULL to
            ; zero. Ask the public COM API directly before classifying the window.
            id := this.ManagerWindowId(hwnd)
            if id = "" && !allowUnassigned
                throw Error("Window has no assigned virtual desktop", , Format("HWND 0x{:X}", hwnd))
        }
        return id
    }

    Manager() {
        if !this.HasOwnProp("DesktopManager")
            this.DesktopManager := ComObject("{AA509086-5CA9-4C25-8F95-589D3C07B48A}",
                "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}")
        return this.DesktopManager
    }

    ManagerWindowId(hwnd) {
        desktopId := Buffer(16, 0)
        ; IVirtualDesktopManager::GetWindowDesktopId, vtable slot 4. Unlike
        ; the DLL's struct return, this has an explicit GUID output parameter.
        ; Preserve HRESULT: failed calls are not unassigned windows. Cleanup
        ; may separately recognize an inactive, untracked application frame.
        hr := ComCall(4, this.Manager(), "Ptr", hwnd, "Ptr", desktopId, "Int")
        if hr != 0
            throw VDWindowQueryError(hwnd, hr)
        if !(NumGet(desktopId, 0, "UInt64") | NumGet(desktopId, 8, "UInt64"))
            return ""
        return this.FormatGuid(desktopId.Ptr)
    }

    Index(id) {
        storage := Buffer(31, 0)
        pointer := (storage.Ptr + 15) & ~15
        if DllCall("ole32\CLSIDFromString", "Str", id, "Ptr", pointer, "Int") < 0
            throw Error("Invalid desktop GUID")
        index := this.Int("GetDesktopNumberById", "Ptr", pointer)
        if this.Id(index) != id
            throw Error("Desktop GUID/index round trip failed")
        return index
    }

    Snapshot() {
        count := this.Int("GetDesktopCount")
        if count < 1
            throw Error("Invalid desktop count")
        ids := [], seen := Map()
        loop count {
            id := this.Id(A_Index - 1)
            if seen.Has(id) || this.Index(id) != A_Index - 1
                throw Error("Unstable desktop list or GUID ABI mismatch")
            ids.Push(id)
            seen[id] := true
        }
        if this.Int("GetDesktopCount") != count
            throw Error("Desktop count changed while querying")
        return ids
    }

    Current() {
        index := this.Int("GetCurrentDesktopNumber")
        id := this.Id(index)
        if this.Index(id) != this.Int("GetCurrentDesktopNumber")
            throw Error("Current desktop changed while querying")
        return id
    }

    Pinned(hwnd) {
        windowPin := this.Int("IsPinnedWindow", "Ptr", hwnd)
        appPin := this.Int("IsPinnedApp", "Ptr", hwnd)
        if windowPin > 1 || appPin > 1
            throw Error("Invalid pinned-window status")
        return windowPin || appPin
    }

    Create() => this.Id(this.Int("CreateDesktop"))
    Reorder(id, index) => this.Success("MoveDesktop", "Int", this.Index(id), "Int", index)
    MoveWindow(hwnd, id) => this.Success("MoveWindowToDesktopNumber", "Ptr", hwnd, "Int", this.Index(id))
    Go(id) => this.Success("GoToDesktopNumber", "Int", this.Index(id))

    Remove(id, fallback) {
        if id = fallback || this.Int("GetDesktopCount") <= 1
            throw Error("Refusing to remove the last/current fallback desktop")
        removeIndex := this.Index(id), fallbackIndex := this.Index(fallback)
        ; Recheck both identities immediately before the index-based native call.
        if this.Id(removeIndex) != id || this.Id(fallbackIndex) != fallback
            throw Error("Desktop indices changed before removal")
        this.Success("RemoveDesktop", "Int", removeIndex, "Int", fallbackIndex)
    }
}
