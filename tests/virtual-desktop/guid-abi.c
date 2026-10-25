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
