#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <commctrl.h>
#include <stdio.h>
#include <wchar.h>

static FILE *report;
static BOOL painted, restoreOnShow;
static const char *phase = "first";
static LRESULT CALLBACK Observe(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR id, DWORD_PTR reference) {
    (void)id; (void)reference;
    if (message == WM_WINDOWPOSCHANGING && !IsWindowVisible(window)) {
        WINDOWPOS *position = (WINDOWPOS *)lparam;
        if (!(position->flags & SWP_SHOWWINDOW) && !(position->flags & SWP_NOMOVE)) {
            /* Model a host resizing itself for the destination DPI while hidden. */
            position->cx = position->x >= 640 ? 200 : 240;
            position->cy = position->x >= 640 ? 120 : 160;
            position->flags &= ~SWP_NOSIZE;
        }
    }
    if (message == WM_PAINT && !painted) {
        painted = TRUE;
        RECT rect; GetWindowRect(window, &rect);
        fprintf(report, "%s %ld %ld %ld %ld %d\n", phase, rect.left, rect.top,
            rect.right - rect.left, rect.bottom - rect.top,
            GetPropW(window, L"Keybind.Placement.Done.v1") != NULL);
        fflush(report);
    }
    return DefSubclassProc(window, message, wparam, lparam);
}
static BOOL WaitForFile(const WCHAR *path, const WCHAR *suffix) {
    WCHAR signal[32768];
    if (swprintf(signal, 32768, L"%ls%ls", path, suffix) < 0) return FALSE;
    DWORD started = GetTickCount();
    while (GetFileAttributesW(signal) == INVALID_FILE_ATTRIBUTES) {
        if (GetTickCount() - started > 5000) return FALSE;
        MSG message;
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message); DispatchMessageW(&message);
        }
        Sleep(10);
    }
    return TRUE;
}
static void Paint(HWND window) {
    painted = FALSE;
    if (restoreOnShow)
        SetWindowPos(window, NULL, 20, 548, 240, 160, SWP_SHOWWINDOW | SWP_NOACTIVATE | SWP_NOZORDER);
    else
        ShowWindow(window, SW_SHOWNOACTIVATE);
    UpdateWindow(window);
}
int wmain(int argc, wchar_t **argv) {
    if (argc < 3) return 2;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    report = _wfopen(argv[1], L"w");
    if (!report) return 3;
    if (argc > 3) {
        WCHAR path[32768]; GetModuleFileNameW(NULL, path, 32768);
        WCHAR *file = wcsrchr(path, L'\\'); if (!file) return 4;
        wcscpy(file + 1, sizeof(void *) == 8 ? L"..\\KeybindPlacement64.dll" : L"..\\KeybindPlacement32.dll");
        HMODULE library = LoadLibraryExW(path, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
        DWORD (WINAPI *join)(void) = library ? (void *)GetProcAddress(library, "PlacementJoin") : NULL;
        if (!join || join()) return 5;
    }
    restoreOnShow = !wcscmp(argv[2], L"position");
    HWND window = CreateWindowExW(0, L"#32770", L"Native Run fixture", WS_OVERLAPPEDWINDOW,
        restoreOnShow ? 100 : 20, restoreOnShow ? 100 : 548,
        restoreOnShow ? 180 : 240, restoreOnShow ? 100 : 160, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!window || !CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE,
        10, 10, 100, 20, window, (HMENU)(UINT_PTR)0x3002, GetModuleHandleW(NULL), NULL)
        || !SetWindowSubclass(window, Observe, 1, 0)) return 6;
    fprintf(report, "ready\n"); fflush(report);
    if (!WaitForFile(argv[1], L".go")) return 7;
    Paint(window);
    if (!wcscmp(argv[2], L"reuse") || !wcscmp(argv[2], L"restart") || !wcscmp(argv[2], L"dragged")) {
        if (!wcscmp(argv[2], L"dragged"))
            SetWindowPos(window, NULL, 740, 400, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
        ShowWindow(window, SW_HIDE);
        fprintf(report, "hidden %d\n", GetPropW(window, L"Keybind.Placement.Done.v1") != NULL); fflush(report);
        if (!WaitForFile(argv[1], L".again")) return 8;
        phase = "reused"; Paint(window);
        ShowWindow(window, SW_HIDE);
        SetWindowPos(window, NULL, 100, 100, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
        phase = "unrequested"; Paint(window);
    }
    DestroyWindow(window);
    fclose(report);
    return 0;
}
