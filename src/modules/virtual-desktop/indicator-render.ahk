; Premultiplied BGRA surfaces shared by the antialiased card and shadow.
VDIndicatorCreateShadow(layout, image := 0) {
    if !IsObject(image)
        image := VDIndicatorCachedShadow(layout)
    shadow := Gui("+AlwaysOnTop +ToolWindow -Caption -Border -DPIScale +E0x08080020",
        "Keybind desktop indicator shadow")
    try {
        x := layout.X - image.Padding, y := layout.Y - image.Padding
        VDIndicatorUpdateImage(shadow, image, x, y)
        shadow.Show("NoActivate x" x " y" y " w" image.Width " h" image.Height)
        return shadow
    }
    catch as err {
        shadow.Destroy()
        throw err
    }
}

; DllCall otherwise LoadLibrary/FreeLibrary's nonresident DLLs around individual
; calls. GDI+ objects and its startup token must outlive ALL of those calls.
class VDIndicatorGraphicsRuntime {
    __New() {
        this.Module := DllCall("LoadLibraryExW", "Str", A_WinDir "\System32\gdiplus.dll",
            "Ptr", 0, "UInt", 0x800, "Ptr")
        this.Token := 0
        this.Users := 0
        if !this.Module
            throw OSError(, , "Cannot load desktop indicator GDI+")
        try {
            this.Procs := Map()
            for name in ["GdiplusStartup", "GdiplusShutdown", "GdipCreateBitmapFromScan0",
                "GdipGetImageGraphicsContext", "GdipSetTextRenderingHint", "GdipCreateFontFamilyFromName",
                "GdipGetGenericFontFamilySansSerif", "GdipCreateFont", "GdipCreateStringFormat",
                "GdipSetStringFormatAlign", "GdipSetStringFormatLineAlign", "GdipCreateSolidFill",
                "GdipDrawString", "GdipFlush", "GdipDeleteBrush", "GdipDeleteStringFormat",
                "GdipDeleteFont", "GdipDeleteFontFamily", "GdipDeleteGraphics", "GdipDisposeImage"] {
                address := DllCall("GetProcAddress", "Ptr", this.Module, "AStr", name, "Ptr")
                if !address
                    throw Error("Desktop indicator GDI+ export missing: " name)
                this.Procs[name] := address
            }
            startup := Buffer(24, 0), token := 0
            NumPut "UInt", 1, startup
            VDIndicatorGdip(this.Call("GdiplusStartup", "Ptr*", &token,
                "Ptr", startup, "Ptr", 0, "Int"), "startup")
            this.Token := token
            this.ExitHandler := this.Stop.Bind(this)
            OnExit this.ExitHandler
        }
        catch as err {
            if this.Token
                this.Call("GdiplusShutdown", "Ptr", this.Token)
            this.Token := 0
            DllCall("FreeLibrary", "Ptr", this.Module)
            this.Module := 0
            throw err
        }
    }

    Call(name, parameters*) => DllCall(this.Procs[name], parameters*)

    Stop(*) {
        ; Exit may interrupt a render before its finally block. In that case
        ; let process teardown reclaim it, rather than invalidating live objects.
        if this.Users || !this.Module
            return
        if this.Token
            this.Call("GdiplusShutdown", "Ptr", this.Token)
        this.Token := 0
        DllCall("FreeLibrary", "Ptr", this.Module)
        this.Module := 0
    }
}

VDIndicatorGraphics() {
    static runtime := VDIndicatorGraphicsRuntime()
    if !runtime.Module || !runtime.Token
        throw Error("Desktop indicator renderer is stopped")
    return runtime
}

VDIndicatorCachedCard(layout, text, light) {
    static cache := Map()
    key := layout.Width "|" layout.Height "|" layout.Radius "|" layout.FontHeight "|" light "|" text
    if cache.Has(key)
        return cache[key]
    image := VDIndicatorCardImage(layout, text, light)
    cache[key] := image
    VDIndicatorTrimCache(cache, 24)
    return image
}

VDIndicatorCachedShadow(layout) {
    static cache := Map()
    key := layout.Width "|" layout.Height "|" layout.Radius "|" layout.Scale
    if cache.Has(key)
        return cache[key]
    image := VDIndicatorShadowImage(layout)
    cache[key] := image
    VDIndicatorTrimCache(cache, 6)
    return image
}

VDIndicatorTrimCache(cache, limit) {
    while cache.Count > limit {
        for key in cache {
            cache.Delete(key)
            break
        }
    }
}

VDIndicatorUpdateImage(window, image, x, y) {
    screen := 0, memory := 0, bitmap := 0, oldBitmap := 0
    try {
        screen := DllCall("GetDC", "Ptr", 0, "Ptr")
        memory := DllCall("gdi32\CreateCompatibleDC", "Ptr", screen, "Ptr")
        if !screen || !memory
            throw OSError(, , "Cannot create desktop indicator surface DC")
        header := Buffer(40, 0), bits := 0
        NumPut "UInt", 40, "Int", image.Width, "Int", -image.Height,
            "UShort", 1, "UShort", 32, header
        bitmap := DllCall("gdi32\CreateDIBSection", "Ptr", memory, "Ptr", header,
            "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
        if !bitmap || !bits
            throw OSError(, , "Cannot create desktop indicator surface bitmap")
        DllCall("RtlMoveMemory", "Ptr", bits, "Ptr", image.Pixels, "UPtr", image.Pixels.Size)
        oldBitmap := DllCall("gdi32\SelectObject", "Ptr", memory, "Ptr", bitmap, "Ptr")
        if !oldBitmap || oldBitmap = -1
            throw OSError(, , "Cannot select desktop indicator surface bitmap")
        position := Buffer(8), size := Buffer(8), origin := Buffer(8, 0), blend := Buffer(4, 0)
        NumPut "Int", x, "Int", y, position
        NumPut "Int", image.Width, "Int", image.Height, size
        NumPut "UChar", 255, "UChar", 1, blend, 2 ; AC_SRC_ALPHA, premultiplied BGRA.
        if !DllCall("UpdateLayeredWindow", "Ptr", window.Hwnd, "Ptr", screen,
            "Ptr", position, "Ptr", size, "Ptr", memory, "Ptr", origin,
            "UInt", 0, "Ptr", blend, "UInt", 2, "Int")
            throw OSError(, , "Cannot draw desktop indicator surface")
    }
    finally {
        if oldBitmap && oldBitmap != -1
            DllCall("gdi32\SelectObject", "Ptr", memory, "Ptr", oldBitmap, "Ptr")
        if bitmap
            DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        if memory
            DllCall("gdi32\DeleteDC", "Ptr", memory)
        if screen
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
    }
}

VDIndicatorCardImage(layout, text, light) {
    width := layout.Width, height := layout.Height
    pixels := Buffer(width * height * 4, 0)
    color := light ? 0xEAF0FB : 0x292D35
    red := (color >> 16) & 255, green := (color >> 8) & 255, blue := color & 255
    radius := Min(layout.Radius, width / 2, height / 2)
    halfWidth := width / 2, halfHeight := height / 2
    loop height {
        row := A_Index - 1
        qy := Abs(row + 0.5 - halfHeight) - (halfHeight - radius)
        loop width {
            column := A_Index - 1
            qx := Abs(column + 0.5 - halfWidth) - (halfWidth - radius)
            distance := Sqrt(Max(qx, 0) ** 2 + Max(qy, 0) ** 2)
                + Min(Max(qx, qy), 0) - radius
            ; One physical pixel of coverage smooths the edge at every DPI.
            alpha := Round(245 * Max(0, Min(1, 0.5 - distance)))
            value := (alpha << 24) | (Round(red * alpha / 255) << 16)
                | (Round(green * alpha / 255) << 8) | Round(blue * alpha / 255)
            NumPut "UInt", value, pixels, (row * width + column) * 4
        }
    }
    VDIndicatorDrawText(pixels, width, height, layout.FontHeight, text, light ? 0xFF202124 : 0xFFF3F4F6)
    return {Pixels: pixels, Width: width, Height: height}
}

VDIndicatorDrawText(pixels, width, height, fontHeight, text, color) {
    runtime := VDIndicatorGraphics()
    runtime.Users += 1
    bitmap := 0, graphics := 0, family := 0, font := 0, format := 0, brush := 0
    try {
        VDIndicatorGdip(runtime.Call("GdipCreateBitmapFromScan0", "Int", width,
            "Int", height, "Int", width * 4, "Int", 0xE200B, "Ptr", pixels,
            "Ptr*", &bitmap, "Int"), "bitmap") ; PixelFormat32bppPARGB
        VDIndicatorGdip(runtime.Call("GdipGetImageGraphicsContext", "Ptr", bitmap,
            "Ptr*", &graphics, "Int"), "graphics")
        VDIndicatorGdip(runtime.Call("GdipSetTextRenderingHint", "Ptr", graphics,
            "Int", 3, "Int"), "text antialiasing") ; AntiAliasGridFit, no ClearType color fringes.
        if runtime.Call("GdipCreateFontFamilyFromName", "Str", "Microsoft YaHei UI",
            "Ptr", 0, "Ptr*", &family, "Int") != 0
            VDIndicatorGdip(runtime.Call("GdipGetGenericFontFamilySansSerif",
                "Ptr*", &family, "Int"), "fallback font family")
        VDIndicatorGdip(runtime.Call("GdipCreateFont", "Ptr", family, "Float", fontHeight,
            "Int", 0, "Int", 2, "Ptr*", &font, "Int"), "font") ; UnitPixel
        VDIndicatorGdip(runtime.Call("GdipCreateStringFormat", "Int", 0x1000,
            "UShort", 0, "Ptr*", &format, "Int"), "text format") ; NoWrap
        VDIndicatorGdip(runtime.Call("GdipSetStringFormatAlign", "Ptr", format,
            "Int", 1, "Int"), "horizontal alignment")
        VDIndicatorGdip(runtime.Call("GdipSetStringFormatLineAlign", "Ptr", format,
            "Int", 1, "Int"), "vertical alignment")
        VDIndicatorGdip(runtime.Call("GdipCreateSolidFill", "UInt", color,
            "Ptr*", &brush, "Int"), "text brush")
        bounds := Buffer(16, 0)
        NumPut "Float", width, "Float", height, bounds, 8
        VDIndicatorGdip(runtime.Call("GdipDrawString", "Ptr", graphics, "Str", text,
            "Int", -1, "Ptr", font, "Ptr", bounds, "Ptr", format, "Ptr", brush,
            "Int"), "text drawing")
        VDIndicatorGdip(runtime.Call("GdipFlush", "Ptr", graphics, "Int", 1,
            "Int"), "text flush")
    }
    finally {
        if brush
            runtime.Call("GdipDeleteBrush", "Ptr", brush)
        if format
            runtime.Call("GdipDeleteStringFormat", "Ptr", format)
        if font
            runtime.Call("GdipDeleteFont", "Ptr", font)
        if family
            runtime.Call("GdipDeleteFontFamily", "Ptr", family)
        if graphics
            runtime.Call("GdipDeleteGraphics", "Ptr", graphics)
        if bitmap
            runtime.Call("GdipDisposeImage", "Ptr", bitmap)
        runtime.Users -= 1
    }
}

VDIndicatorGdip(status, operation) {
    if status != 0
        throw Error("Desktop indicator " operation " failed (GDI+ status " status ")")
}

VDIndicatorShadowImage(layout) {
    scale := layout.Scale
    padding := Max(1, Round(12 * scale)), offset := 2 * scale, sigma := 3 * scale
    width := layout.Width + 2 * padding, height := layout.Height + 2 * padding
    pixels := Buffer(width * height * 4, 0)
    radius := Min(layout.Radius, layout.Width / 2, layout.Height / 2)
    halfWidth := layout.Width / 2, halfHeight := layout.Height / 2
    ; Rounded-rectangle distance produces a smooth falloff around the corners.
    ; Leave the card's interior transparent so its translucent fill stays intact.
    loop height {
        row := A_Index - 1
        y := row - padding + 0.5 - halfHeight
        loop width {
            column := A_Index - 1
            x := column - padding + 0.5 - halfWidth
            qx := Abs(x) - (halfWidth - radius)
            qy := Abs(y) - (halfHeight - radius)
            distance := Sqrt(Max(qx, 0) ** 2 + Max(qy, 0) ** 2)
                + Min(Max(qx, qy), 0) - radius
            if distance <= 0
                continue
            qy := Abs(y - offset) - (halfHeight - radius)
            distance := Max(0, Sqrt(Max(qx, 0) ** 2 + Max(qy, 0) ** 2)
                + Min(Max(qx, qy), 0) - radius)
            alpha := Round(44 * Exp(-(distance ** 2) / (2 * sigma ** 2)))
            NumPut "UInt", alpha << 24, pixels, (row * width + column) * 4
        }
    }
    return {Pixels: pixels, Width: width, Height: height, Padding: padding}
}

