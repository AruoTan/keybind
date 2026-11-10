#ifndef KEYBIND_PLACEMENT_PROTOCOL_H
#define KEYBIND_PLACEMENT_PROTOCOL_H
#include <windows.h>

#define PLACEMENT_ABI 2
#define PLACEMENT_MAPPING L"Local\\Keybind.Placement.v2"
#define PLACEMENT_DONE L"Keybind.Placement.Done.v1"

/* Fixed-width fields: the x86 host reads the x64 controller's mapping. */
typedef struct {
    DWORD abi, owner;
    FILETIME born;
    volatile LONG enabled, blocked, heartbeat;
    volatile LONG host32, host32Error;
    volatile LONG placed, skipped, failed;
    volatile LONG64 gates; /* High 32 bits hold the controller epoch. */
} PlacementShared;
_Static_assert(sizeof(PlacementShared) == 56, "placement IPC layout changed");

typedef DWORD (WINAPI *PlacementStartFn)(void);
typedef void (WINAPI *PlacementStopFn)(void);
#endif
