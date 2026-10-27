/* Test-only Windows x64 DLL. No shell/virtual desktop APIs are called.
 * A 16-byte aggregate exercises the same C ABI as the upstream Rust GUID. */
#include <stdint.h>
#include <string.h>

typedef struct { uint32_t a; uint16_t b, c; uint8_t d[8]; } Guid;
static const Guid desktop = {0xFEDCBA98, 0x7654, 0x3210, {0x89, 0xAB, 0xCD, 0xEF, 1, 2, 3, 4}};
static const Guid zero = {0};
#define API __declspec(dllexport)

API int GetDesktopCount(void) { return 1; }
API int GetCurrentDesktopNumber(void) { return 0; }
API Guid GetDesktopIdByNumber(int number) { return number == 0 ? desktop : zero; }
API int GetDesktopNumberById(Guid id) { return memcmp(&id, &desktop, sizeof(Guid)) == 0 ? 0 : -1; }
API Guid GetWindowDesktopId(void *hwnd) { return (uintptr_t)hwnd == 101 ? desktop : zero; }
API int IsPinnedWindow(void *hwnd) { return (uintptr_t)hwnd == 101 ? 0 : -1; }
API int IsPinnedApp(void *hwnd) { return (uintptr_t)hwnd == 101 ? 0 : -1; }
API int CreateDesktop(void) { return -1; }
API int MoveDesktop(int number, int index) { (void)number; (void)index; return -1; }
API int MoveWindowToDesktopNumber(void *hwnd, int number) { (void)hwnd; (void)number; return -1; }
API int GoToDesktopNumber(int number) { (void)number; return -1; }
API int RemoveDesktop(int number, int fallback) { (void)number; (void)fallback; return -1; }

/* The real public COM call uses HRESULT + GUID*. Keep failures distinct from
 * S_OK/GUID_NULL; no Windows desktop manager is needed to exercise ComCall. */
static int ManagerWindowId(void *self, void *hwnd, Guid *id) {
    (void)self;
    *id = zero;
    switch ((uintptr_t)hwnd) {
        case 102: return 0;             /* successful unassigned window */
        case 103: return (int)0x80004005; /* E_FAIL, output must not be trusted */
        case 104: *id = desktop; return 0; /* recovered DLL query */
        case 105: return 1;             /* S_FALSE is not a confirmed result */
        case 106: return (int)0x8002802B; /* untracked view; not GUID_NULL */
        default: return (int)0x80070057; /* E_INVALIDARG */
    }
}
static void *manager_vtable[] = {0, 0, 0, 0, (void *)ManagerWindowId, 0};
static struct { void **vtable; } manager = {manager_vtable};
API void *GetTestDesktopManager(void) { return &manager; }
API void *InvalidGuidReturn(Guid *output, int number) {
    (void)number;
    *output = desktop;
    return 0; /* Wrong sret pointer, even though the buffer contains a GUID. */
}
