/* A host may not expose every Common Controls subclass entry point. */
#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char *missing;
static unsigned lookups;
static HMODULE WINAPI TestLoadLibraryExW(LPCWSTR name, HANDLE file, DWORD flags) {
    if (missing && !strcmp(missing, "library")) return NULL;
    return LoadLibraryExW(name, file, flags);
}
static FARPROC WINAPI TestGetProcAddress(HMODULE library, LPCSTR name) {
    ++lookups;
    if (missing && !strcmp(missing, name)) return NULL;
    return GetProcAddress(library, name);
}
#define LoadLibraryExW TestLoadLibraryExW
#define GetProcAddress TestGetProcAddress
#include "../../src/native/window-placement/hook.c"
#undef GetProcAddress
#undef LoadLibraryExW

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL: %s at %d\n", #value, __LINE__); return 1; } } while (0)
int wmain(void) {
    const char *cases[] = {NULL, "GetWindowSubclass", "SetWindowSubclass",
        "RemoveWindowSubclass", "DefSubclassProc", "library"};
    for (unsigned i = 0; i < sizeof(cases) / sizeof(*cases); ++i) {
        missing = cases[i]; lookups = 0;
        CHECK(SubclassAvailable() == (missing == NULL));
        unsigned once = lookups;
        CHECK(SubclassAvailable() == (missing == NULL) && lookups == once);
        if (missing) {
            CHECK(!subclassApi.Library && !subclassApi.Set && !subclassApi.Get
                && !subclassApi.Remove && !subclassApi.Next);
        } else {
            CHECK(subclassApi.Library && subclassApi.Set && subclassApi.Get
                && subclassApi.Remove && subclassApi.Next);
            FreeLibrary(subclassApi.Library);
        }
        ZeroMemory(&subclassApi, sizeof(subclassApi));
        InitOnceInitialize(&subclassOnce);
    }
    puts("PASS: optional Common Controls binding, each missing subclass export, provider load failure, and cached availability");
    return 0;
}
