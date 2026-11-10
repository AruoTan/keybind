/* Two work areas inside the test display; production binaries never include this file. */
#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <dwmapi.h>
static inline HMONITOR TestMonitorPoint(POINT point, DWORD flags) {
    (void)flags; return (HMONITOR)(ULONG_PTR)(point.x < 640 ? 1 : 2);
}
static inline HMONITOR TestMonitorRect(LPCRECT rect, DWORD flags) {
    POINT point = {(rect->left + rect->right) / 2, (rect->top + rect->bottom) / 2};
    return TestMonitorPoint(point, flags);
}
static inline HMONITOR TestMonitorWindow(HWND window, DWORD flags) {
    RECT rect; return GetWindowRect(window, &rect) ? TestMonitorRect(&rect, flags) : NULL;
}
static inline BOOL TestMonitorInfo(HMONITOR monitor, LPMONITORINFO info) {
    if (monitor != (HMONITOR)(ULONG_PTR)1 && monitor != (HMONITOR)(ULONG_PTR)2) return FALSE;
    LONG left = monitor == (HMONITOR)(ULONG_PTR)1 ? 0 : 640;
    info->rcMonitor = (RECT){left, 0, left + 640, 720}; info->rcWork = info->rcMonitor;
    info->dwFlags = monitor == (HMONITOR)(ULONG_PTR)1 ? MONITORINFOF_PRIMARY : 0;
    return TRUE;
}
static inline BOOL TestEnumMonitors(HDC dc, LPCRECT rect, MONITORENUMPROC callback, LPARAM data) {
    (void)dc; (void)rect;
    RECT a = {0, 0, 640, 720}, b = {640, 0, 1280, 720};
    return callback((HMONITOR)(ULONG_PTR)1, NULL, &a, data)
        && callback((HMONITOR)(ULONG_PTR)2, NULL, &b, data);
}
static inline HRESULT TestCloak(HWND window, DWORD attribute, PVOID value, DWORD size) {
    (void)window; (void)attribute; (void)size; *(DWORD *)value = 0; return S_OK;
}
#define MonitorFromPoint TestMonitorPoint
#define MonitorFromRect TestMonitorRect
#define MonitorFromWindow TestMonitorWindow
#define GetMonitorInfoW TestMonitorInfo
#define EnumDisplayMonitors TestEnumMonitors
#define DwmGetWindowAttribute TestCloak
