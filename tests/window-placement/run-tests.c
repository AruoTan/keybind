#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include "../../src/native/window-placement/protocol.h"
#undef PLACEMENT_MAPPING
#define PLACEMENT_MAPPING L"Local\\Keybind.Placement.RunTests.v3"
#include "../../src/native/window-placement/hook.c"
#include <stdio.h>
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL: %s at %d\n", #value, __LINE__); return 1; } } while (0)
int wmain(void) {
    static PlacementShared memory;
    shared = &memory; shared->owner = GetCurrentProcessId();
    CHECK(!PlacementRun(NULL));
    CHECK(!PlacementRun(L"MISSING"));
    CHECK(PlacementRun(L"TEST_RIGHT"));
    CHECK(TakeRunTarget() == (HMONITOR)(ULONG_PTR)2);
    CHECK(!TakeRunTarget());
    CHECK(PlacementRun(L"TEST_LEFT"));
    shared->runDeadline = GetTickCount() - 1;
    CHECK(!TakeRunTarget());
    CHECK(PlacementRun(L"TEST_LEFT"));
    CHECK(PlacementRun(L"TEST_RIGHT"));
    CHECK(TakeRunTarget() == (HMONITOR)(ULONG_PTR)2);
    shared->owner = 0;
    CHECK(!PlacementRun(L"TEST_LEFT"));
    puts("PASS: Run request identity, device validation, one-shot consumption, expiry, and replacement");
    return 0;
}
