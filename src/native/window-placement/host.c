#define UNICODE 1
#define _UNICODE 1
#include "protocol.h"
#include <wchar.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command, int show) {
    (void)instance; (void)previous; (void)command; (void)show;
    WCHAR path[32768];
    if (!GetModuleFileNameW(NULL, path, 32768)) return 1;
    WCHAR *name = wcsrchr(path, L'\\');
    if (!name) return 1;
    wcscpy(name + 1, L"KeybindPlacement32.dll");
    HMODULE library = LoadLibraryExW(path, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!library) return (int)GetLastError();
    PlacementStartFn join = (PlacementStartFn)(void *)GetProcAddress(library, "PlacementJoin");
    PlacementStopFn stop = (PlacementStopFn)(void *)GetProcAddress(library, "PlacementStop");
    BOOL (WINAPI *alive)(void) = (void *)GetProcAddress(library, "PlacementAlive");
    if (!join || !stop || !alive) return ERROR_PROC_NOT_FOUND;
    DWORD error = join();
    if (error) return (int)error;
    MSG message;
    while (alive()) {
        MsgWaitForMultipleObjects(0, NULL, FALSE, 250, QS_ALLINPUT);
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) goto done;
            TranslateMessage(&message); DispatchMessageW(&message);
        }
    }
done:
    stop(); FreeLibrary(library);
    return 0;
}
