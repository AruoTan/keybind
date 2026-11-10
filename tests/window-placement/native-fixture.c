#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <commctrl.h>
#include <stdio.h>
#include <wchar.h>

typedef struct { const char *name; BOOL paint, restore, destroy, spawn; } State;
static FILE *report;
static BOOL traceMax;
static LRESULT (WINAPI *nextSubclass)(HWND, UINT, WPARAM, LPARAM);
static void Paint(HWND window);
static State early = {"early-dialog", FALSE, FALSE, FALSE, FALSE};
static LRESULT CALLBACK TraceHook(int code, WPARAM wparam, LPARAM lparam) {
    if (traceMax && code == HCBT_MINMAX) {
        fprintf(report, "cbt-max %ld visible=%d zoomed=%d\n", (LONG)lparam, IsWindowVisible((HWND)wparam), IsZoomed((HWND)wparam));
        fflush(report);
    }
    return CallNextHookEx(NULL, code, wparam, lparam);
}
static LRESULT CALLBACK CrashOnCommit(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR id, DWORD_PTR reference) {
    (void)id; (void)reference;
    if (message == WM_WINDOWPOSCHANGED && GetPropW(window, L"Keybind.Placement.Done.v1")) {
        fprintf(report, "crash-after-routing\n"); fflush(report);
        TerminateProcess(GetCurrentProcess(), 42);
    }
    return nextSubclass(window, message, wparam, lparam);
}
static LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    State *state = (State *)GetWindowLongPtrW(window, GWLP_USERDATA);
    if (message == WM_NCCREATE) {
        state = ((CREATESTRUCTW *)lparam)->lpCreateParams;
        SetWindowLongPtrW(window, GWLP_USERDATA, (LONG_PTR)state);
    }
    if (state && message == WM_WINDOWPOSCHANGING) {
        WINDOWPOS *position = (WINDOWPOS *)lparam;
        if (traceMax) { fprintf(report, "position %u %d %d visible=%d zoomed=%d\n", position->flags, position->x, position->y, IsWindowVisible(window), IsZoomed(window)); fflush(report); }
        if (position->flags & SWP_SHOWWINDOW) {
            if (state->destroy) { DestroyWindow(window); return 0; }
            if (state->restore) {
                position->x = 100; position->y = 100; position->flags &= ~SWP_NOMOVE;
            }
        }
    }
    if (state && message == WM_SHOWWINDOW && wparam && state->spawn) {
        state->spawn = FALSE;
        SetCursorPos(800, 300);
        HWND dialog = CreateWindowExW(0, L"Keybind.NativePlacement.Fixture", L"Early dialog", WS_OVERLAPPEDWINDOW,
            740, 100, 220, 140, window, NULL, GetModuleHandleW(NULL), &early);
        Paint(dialog);
    }
    if (state && message == WM_PAINT && !state->paint) {
        state->paint = TRUE;
        RECT rect; GetWindowRect(window, &rect);
        fprintf(report, "%s %ld %ld %ld %ld %d\n", state->name, rect.left, rect.top,
            rect.right - rect.left, rect.bottom - rect.top,
            GetPropW(window, L"Keybind.Placement.Done.v1") != NULL);
        fflush(report);
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
static void Paint(HWND window) {
    ShowWindow(window, SW_SHOWNOACTIVATE);
    UpdateWindow(window);
    MSG message;
    for (unsigned i = 0; i < 10; ++i) {
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message); DispatchMessageW(&message);
        }
        Sleep(5);
    }
}
int wmain(int argc, wchar_t **argv) {
    if (argc != 3 && argc != 4) return 2;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    report = _wfopen(argv[1], L"w");
    if (!report) return 3;
    traceMax = !wcscmp(argv[2], L"maximized");
    if (traceMax) SetWindowsHookExW(WH_CBT, TraceHook, NULL, GetCurrentThreadId());
    WNDCLASSW type = {0};
    type.lpfnWndProc = Procedure; type.hInstance = GetModuleHandleW(NULL);
    type.lpszClassName = L"Keybind.NativePlacement.Fixture"; type.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    if (!RegisterClassW(&type)) return 4;
    if (argc == 4 && !wcscmp(argv[3], L"--local-hook")) {
        /* Wine lacks the Windows global injection path. Exercise the same DLL in this process. */
        WCHAR path[32768]; GetModuleFileNameW(NULL, path, 32768);
        WCHAR *name = wcsrchr(path, L'\\');
        if (!name) return 6;
        wcscpy(name + 1, sizeof(void *) == 8 ? L"KeybindPlacement64.dll" : L"KeybindPlacement32.dll");
        HMODULE library = LoadLibraryExW(path, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!library) return 7;
        DWORD (WINAPI *join)(void) = (void *)GetProcAddress(library, "PlacementJoin");
        if (!join) return 8;
        DWORD error = join();
        /* The pre-existing-window scenario runs before the controller starts. */
        if (error && wcscmp(argv[2], L"existing")) return 9;
    }
    State root = {"first", FALSE, FALSE, FALSE, FALSE};
    BOOL visible = !wcscmp(argv[2], L"visible"), defaults = !wcscmp(argv[2], L"default");
    HWND window = CreateWindowExW(0, type.lpszClassName, L"Placement native fixture",
        WS_OVERLAPPEDWINDOW | (visible ? WS_VISIBLE : 0),
        defaults ? CW_USEDEFAULT : 100, defaults ? CW_USEDEFAULT : 100,
        240, 160, NULL, NULL, type.hInstance, &root);
    if (!window) return 5;
    fprintf(report, "hook-module %d\n", GetModuleHandleW(sizeof(void *) == 8 ? L"KeybindPlacement64.dll" : L"KeybindPlacement32.dll") != NULL);
    fflush(report);
    if (!wcscmp(argv[2], L"legacy")) {
        HMODULE controls = GetModuleHandleW(L"comctl32.dll");
        fprintf(report, "subclass-supported %d\n", controls && GetProcAddress(controls, "GetWindowSubclass") != NULL);
        fflush(report);
    }
    if (!wcscmp(argv[2], L"crash")) {
        HMODULE controls = GetModuleHandleW(L"comctl32.dll");
        BOOL (WINAPI *set)(HWND, SUBCLASSPROC, UINT_PTR, DWORD_PTR) =
            controls ? (void *)GetProcAddress(controls, "SetWindowSubclass") : NULL;
        nextSubclass = controls ? (void *)GetProcAddress(controls, "DefSubclassProc") : NULL;
        if (!set || !nextSubclass || !set(window, CrashOnCommit, 1, 0)) return 10;
    }
    if (!wcscmp(argv[2], L"existing") || !wcscmp(argv[2], L"blocked-hidden") || !wcscmp(argv[2], L"crash")) {
        fprintf(report, "ready\n"); fflush(report);
        WCHAR go[32768]; swprintf(go, 32768, L"%ls.go", argv[1]);
        DWORD deadline = GetTickCount() + 5000;
        while (GetFileAttributesW(go) == INVALID_FILE_ATTRIBUTES && (LONG)(deadline - GetTickCount()) > 0) Sleep(10);
    }
    root.restore = !wcscmp(argv[2], L"restore");
    root.destroy = !wcscmp(argv[2], L"destroy");
    root.spawn = !wcscmp(argv[2], L"early-dialog");
    if (root.spawn) SetCursorPos(100, 300);
    if (!wcscmp(argv[2], L"maximized")) {
        ShowWindow(window, SW_SHOWMAXIMIZED); UpdateWindow(window);
        WINDOWPLACEMENT placement = {0}; placement.length = sizeof(placement);
        GetWindowPlacement(window, &placement);
        fprintf(report, "maximized %ld %d\n", placement.rcNormalPosition.left, IsZoomed(window)); fflush(report);
    } else Paint(window);
    if (root.destroy) {
        fprintf(report, "destroyed %d\n", !IsWindow(window)); fflush(report);
    } else if (!wcscmp(argv[2], L"regular")) {
        SetWindowPos(window, NULL, 100, 100, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        ShowWindow(window, SW_HIDE); root.name = "reshow"; root.paint = FALSE;
        Paint(window);
        State dialog = {"dialog", FALSE, FALSE, FALSE, FALSE};
        HWND child = CreateWindowExW(0, type.lpszClassName, L"Owned placement fixture", WS_OVERLAPPEDWINDOW,
            740, 100, 220, 140, window, NULL, type.hInstance, &dialog);
        Paint(child); DestroyWindow(child);
        State tool = {"tool", FALSE, FALSE, FALSE, FALSE};
        child = CreateWindowExW(WS_EX_TOOLWINDOW, type.lpszClassName, L"Tool fixture", WS_OVERLAPPEDWINDOW,
            100, 100, 220, 140, NULL, NULL, type.hInstance, &tool);
        Paint(child); DestroyWindow(child);
        State popup = {"fullscreen", FALSE, FALSE, FALSE, FALSE};
        child = CreateWindowExW(0, type.lpszClassName, L"Full screen fixture", WS_POPUP,
            0, 0, 640, 720, NULL, NULL, type.hInstance, &popup);
        Paint(child); DestroyWindow(child);
        State passive = {"noactivate", FALSE, FALSE, FALSE, FALSE};
        child = CreateWindowExW(WS_EX_NOACTIVATE, type.lpszClassName, L"Passive fixture", WS_OVERLAPPEDWINDOW,
            100, 100, 220, 140, NULL, NULL, type.hInstance, &passive);
        Paint(child); DestroyWindow(child);
    }
    if (IsWindow(window)) DestroyWindow(window);
    fclose(report);
    return 0;
}
