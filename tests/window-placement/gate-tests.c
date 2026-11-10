/* Exercise the actual cross-architecture gate implementation without a window manager. */
#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include "../../src/native/window-placement/protocol.h"
#undef PLACEMENT_MAPPING
#define PLACEMENT_MAPPING L"Local\\Keybind.Placement.GateTests.v2"
#include "../../src/native/window-placement/hook.c"
#include <stdio.h>

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL: %s at %d\n", #value, __LINE__); return 1; } } while (0)
static WindowState CurrentState(void) {
    WindowState state = {0};
    state.owner = shared->owner; state.born = shared->born;
    state.epoch = (DWORD)(GateValue() >> 32);
    return state;
}
static DWORD WINAPI AbandonGate(void *argument) {
    WindowState *state = argument;
    CHECK(EnterGate(state));
    return 0; /* The process stays alive, keeping the abandoned mutex handle open. */
}
int wmain(int argc, wchar_t **argv) {
    (void)argv;
    HANDLE ready = CreateEventW(NULL, TRUE, FALSE, PLACEMENT_MAPPING L".Test.Ready");
    HANDLE exit = CreateEventW(NULL, TRUE, FALSE, PLACEMENT_MAPPING L".Test.Exit");
    CHECK(ready && exit);
    if (argc > 1) {
        CHECK(Map());
        WindowState state = CurrentState();
        CHECK(EnterGate(&state));
        CHECK(SetEvent(ready));
        CHECK(WaitForSingleObject(exit, 5000) == WAIT_OBJECT_0);
        /* Exit without a window-destruction callback or LeaveGate. */
        ExitProcess(42);
    }
    mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, sizeof(*shared), PLACEMENT_MAPPING);
    CHECK(mapping);
    shared = MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, sizeof(*shared));
    CHECK(shared);
    ZeroMemory(shared, sizeof(*shared));
    shared->abi = PLACEMENT_ABI; shared->owner = GetCurrentProcessId();
    FILETIME exited, kernel, user;
    CHECK(GetProcessTimes(GetCurrentProcess(), &shared->born, &exited, &kernel, &user));
    InterlockedExchange64(&shared->gates, (LONG64)((ULONGLONG)1 << 32));
    WindowState old = CurrentState();
    CHECK(EnterGate(&old));
    /* A restarted controller must not share its gate with old callbacks. */
    InterlockedExchange64(&shared->gates, (LONG64)((ULONGLONG)2 << 32));
    WCHAR executable[32768], command[32780];
    CHECK(GetModuleFileNameW(NULL, executable, 32768));
    CHECK(swprintf(command, 32780, L"\"%ls\" --hold", executable) > 0);
    STARTUPINFOW startup = {0}; startup.cb = sizeof(startup);
    PROCESS_INFORMATION child = {0};
    CHECK(CreateProcessW(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &startup, &child));
    CHECK(WaitForSingleObject(ready, 5000) == WAIT_OBJECT_0);
    CHECK(!PlacementBlock(TRUE));
    LeaveGate(&old);
    CHECK(!PlacementBlock(TRUE));
    CHECK(PlacementBlock(FALSE));
    CHECK(!PlacementBlock(TRUE));
    CHECK(SetEvent(exit));
    CHECK(WaitForSingleObject(child.hProcess, 5000) == WAIT_OBJECT_0);
    DWORD code = 0;
    CHECK(GetExitCodeProcess(child.hProcess, &code) && code == 42);
    CHECK(PlacementBlock(TRUE));
    WindowState next = CurrentState();
    CHECK(!EnterGate(&next));
    PlacementUpdate(FALSE);
    CHECK(shared->blocked);
    CHECK(PlacementBlock(FALSE));
    CHECK(EnterGate(&next));
    CHECK(PlacementBlock(FALSE));
    LeaveGate(&next);
    CHECK(PlacementBlock(TRUE));
    CHECK(PlacementBlock(FALSE));
    CHECK(!EnterGate(&old));
    next = CurrentState();
    HANDLE thread = CreateThread(NULL, 0, AbandonGate, &next, 0, NULL);
    CHECK(thread && WaitForSingleObject(thread, 5000) == WAIT_OBJECT_0);
    CHECK(GetExitCodeThread(thread, &code) && code == 0);
    CHECK(PlacementBlock(TRUE));
    CHECK(shared->blocked);
    CHECK(CloseHandle(next.gate));
    CHECK(CloseHandle(thread));
    CHECK(PlacementBlock(FALSE));
    InterlockedExchange64(&shared->gates, (LONG64)((ULONGLONG)0x80000000u << 32));
    next = CurrentState();
    CHECK(EnterGate(&next)); LeaveGate(&next);
    CHECK(PlacementBlock(TRUE)); CHECK(PlacementBlock(FALSE));
    CloseHandle(child.hThread); CloseHandle(child.hProcess);
    CloseHandle(ready); CloseHandle(exit);
    UnmapViewOfFile(shared); CloseHandle(mapping);
    puts("PASS: native gate ownership, restart isolation, navigation exclusion, heartbeat, high-bit epoch, and recovery after process/thread exit");
    return 0;
}
