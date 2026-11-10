class PlacementBridge {
    __New(allowed) {
        this.Module := 0, this.Host := 0, this.Allowed := allowed
        this.Started := false, this.HostProcess := 0, this.HostDeadline := 0
        this.Functions := Map(), this.LastCounts := "", this.HostReported := false
        this.Timer := ObjBindMethod(this, "Update")
    }

    Start(folder := "") {
        if this.Started
            return
        this.Host := 0, this.HostReported := false, this.LastCounts := ""
        if folder = ""
            folder := A_ScriptDir
        if !FileExist(folder "\KeybindPlacement64.dll")
            folder := A_ScriptDir "\..\dist\windows-x64"
        this.Module := DllCall("LoadLibraryExW", "Str", folder "\KeybindPlacement64.dll",
            "Ptr", 0, "UInt", 0x1100, "Ptr") ; DLL_LOAD_DIR | SYSTEM32
        if !this.Module
            throw OSError(, , "Cannot load KeybindPlacement64.dll")
        for name in ["Start", "Stop", "Update", "Block", "Status"] {
            address := DllCall("GetProcAddress", "Ptr", this.Module, "AStr", "Placement" name, "Ptr")
            if !address
                throw Error("Missing placement export: " name)
            this.Functions[name] := address
        }
        error := DllCall(this.Functions["Start"], "UInt")
        if error
            throw OSError(error, , "Cannot initialize pre-show placement")
        this.Started := true
        this.Update()
        SetTimer this.Timer, 250
        pid := 0
        try Run '"' folder '\keybind-placement32.exe"', folder, "Hide", &pid
        catch as err {
            PlacementLog("Native x86 host unavailable: " err.Message)
            return
        }
        this.Host := pid
        this.HostDeadline := A_TickCount + 3000
        this.HostProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
        PlacementLog("Native pre-show ready; ABI=2; PID=" DllCall("GetCurrentProcessId", "UInt")
            "; x64 hook installed; x86-host-pid=" this.Host)
    }

    Update(*) {
        if !this.Module || !this.Started
            return
        DllCall this.Functions["Update"], "Int", !this.Allowed.Call()
        status := this.Functions["Status"]
        if this.Host && !this.HostReported {
            pid := DllCall(status, "UInt", 0, "UInt"), error := DllCall(status, "UInt", 1, "UInt")
            exitCode := 259
            if this.HostProcess
                DllCall "GetExitCodeProcess", "Ptr", this.HostProcess, "UInt*", &exitCode
            if pid = this.Host || error || exitCode != 259 || A_TickCount >= this.HostDeadline {
                PlacementLog("Native x86 host; ready=" (pid = this.Host && !error)
                    "; pid=" this.Host "; error=" error "; exit-code=" exitCode
                    "; wait-expired=" (A_TickCount >= this.HostDeadline))
                this.HostReported := true
            }
        }
        counts := ("placed=" DllCall(status, "UInt", 2, "UInt")
            "; skipped=" DllCall(status, "UInt", 3, "UInt")
            "; hook-failures=" DllCall(status, "UInt", 4, "UInt"))
        if counts != this.LastCounts {
            this.LastCounts := counts
            PlacementLog("Native pre-show; " counts)
        }
    }

    Block(block) => !this.Module || !this.Started
        || !!DllCall(this.Functions["Block"], "Int", block, "Int")

    Close() {
        SetTimer this.Timer, 0
        if this.Module {
            if this.Started
                DllCall this.Functions["Stop"]
            DllCall "FreeLibrary", "Ptr", this.Module
            this.Module := 0
        }
        this.Started := false
        if this.HostProcess
            DllCall "CloseHandle", "Ptr", this.HostProcess
        this.HostProcess := 0
    }
}
