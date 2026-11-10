#define UNICODE 1
#define _UNICODE 1
#define _WIN32_WINNT 0x0A00
#include "protocol.h"
#include <commctrl.h>
#include <dwmapi.h>
#include <wchar.h>

static HMODULE module;
static HHOOK hook;
static HANDLE mapping, ownerProcess;
static PlacementShared *shared;
static DWORD cachedOwner;
static FILETIME cachedBorn;
static BOOL pinned;
static LONG processKind;
static SRWLOCK connectionLock = SRWLOCK_INIT;
static BOOL controller;
static DWORD hostOwner;
static FILETIME hostBorn;
static DWORD hostEpoch;
static HANDLE navigationGate;

typedef struct {
    HMODULE Library;
    BOOL (WINAPI *Set)(HWND, SUBCLASSPROC, UINT_PTR, DWORD_PTR);
    BOOL (WINAPI *Get)(HWND, SUBCLASSPROC, UINT_PTR, DWORD_PTR *);
    BOOL (WINAPI *Remove)(HWND, SUBCLASSPROC, UINT_PTR);
    LRESULT (WINAPI *Next)(HWND, UINT, WPARAM, LPARAM);
} SubclassApi;
static SubclassApi subclassApi;
static INIT_ONCE subclassOnce = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK LoadSubclassApi(PINIT_ONCE once, PVOID parameter, PVOID *context) {
    (void)once; (void)parameter; (void)context;
    SubclassApi api = {0};
    api.Library = LoadLibraryExW(L"comctl32.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!api.Library) return TRUE;
    api.Set = (void *)GetProcAddress(api.Library, "SetWindowSubclass");
    api.Get = (void *)GetProcAddress(api.Library, "GetWindowSubclass");
    api.Remove = (void *)GetProcAddress(api.Library, "RemoveWindowSubclass");
    api.Next = (void *)GetProcAddress(api.Library, "DefSubclassProc");
    if (api.Set && api.Get && api.Remove && api.Next) {
        /* Retain this provider for callbacks, without changing the host's activation context. */
        subclassApi = api;
    } else FreeLibrary(api.Library);
    return TRUE;
}
static BOOL SubclassAvailable(void) {
    InitOnceExecuteOnce(&subclassOnce, LoadSubclassApi, NULL, NULL);
    return subclassApi.Library != NULL;
}
static ULONGLONG GateValue(void) {
    return (ULONGLONG)InterlockedCompareExchange64(&shared->gates, 0, 0);
}

static BOOL SameTime(FILETIME a, FILETIME b) {
    return a.dwLowDateTime == b.dwLowDateTime && a.dwHighDateTime == b.dwHighDateTime;
}
static BOOL Map(void) {
    if (shared) return TRUE;
    mapping = OpenFileMappingW(FILE_MAP_READ | FILE_MAP_WRITE, FALSE, PLACEMENT_MAPPING);
    if (!mapping) return FALSE;
    shared = MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, sizeof(*shared));
    if (!shared) { CloseHandle(mapping); mapping = NULL; }
    return shared != NULL;
}
static BOOL AliveUnlocked(void) {
    if (!Map() || shared->abi != PLACEMENT_ABI || !shared->owner) return FALSE;
    if (cachedOwner != shared->owner || !SameTime(cachedBorn, shared->born)) {
        if (ownerProcess) CloseHandle(ownerProcess);
        ownerProcess = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, shared->owner);
        FILETIME created, exited, kernel, user;
        if (!ownerProcess || !GetProcessTimes(ownerProcess, &created, &exited, &kernel, &user)
            || !SameTime(created, shared->born)) {
            if (ownerProcess) CloseHandle(ownerProcess);
            ownerProcess = NULL;
            return FALSE;
        }
        cachedOwner = shared->owner; cachedBorn = shared->born;
    }
    return ownerProcess && WaitForSingleObject(ownerProcess, 0) == WAIT_TIMEOUT;
}
static BOOL Alive(void) {
    AcquireSRWLockExclusive(&connectionLock);
    BOOL alive = AliveUnlocked();
    ReleaseSRWLockExclusive(&connectionLock);
    return alive;
}
static BOOL Active(void) {
    return Alive() && shared->enabled && !shared->blocked
        && (DWORD)(GetTickCount() - (DWORD)shared->heartbeat) < 1500;
}
static BOOL ShellProcess(void) {
    LONG kind = InterlockedCompareExchange(&processKind, 0, 0);
    if (kind) return kind == 1;
    WCHAR path[MAX_PATH], *name;
    if (!GetModuleFileNameW(NULL, path, MAX_PATH)) return TRUE;
    name = wcsrchr(path, L'\\'); name = name ? name + 1 : path;
    const WCHAR *excluded[] = {L"StartMenuExperienceHost.exe", L"ShellExperienceHost.exe",
        L"SearchHost.exe", L"SearchApp.exe", L"TextInputHost.exe", L"LockApp.exe",
        L"mstsc.exe", L"msrdc.exe"};
    for (unsigned i = 0; i < sizeof(excluded) / sizeof(*excluded); ++i)
        if (!_wcsicmp(name, excluded[i])) { InterlockedExchange(&processKind, 1); return TRUE; }
    InterlockedExchange(&processKind, 2);
    return FALSE;
}
static BOOL Ordinary(HWND window) {
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE), ex = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & (WS_CHILD | WS_MINIMIZE)) || (ex & WS_EX_NOACTIVATE)
        || ((ex & WS_EX_TOOLWINDOW) && !(ex & WS_EX_APPWINDOW))) return FALSE;
    WCHAR name[128];
    if (!GetClassNameW(window, name, 128)) return FALSE;
    const WCHAR *excluded[] = {L"Progman", L"WorkerW", L"Shell_TrayWnd", L"Shell_SecondaryTrayWnd",
        L"MultitaskingViewFrame", L"XamlExplorerHostIslandWindow", L"tooltips_class32",
        L"#32768", L"NotifyIconOverflowWindow"};
    for (unsigned i = 0; i < sizeof(excluded) / sizeof(*excluded); ++i)
        if (!_wcsicmp(name, excluded[i])) return FALSE;
    return window != GetShellWindow() && window != GetDesktopWindow();
}
static BOOL RunDialog(HWND window) {
    WCHAR name[64], path[MAX_PATH];
    if (!GetDlgItem(window, 0x3002) || !GetClassNameW(window, name, 64) || wcscmp(name, L"#32770")) return FALSE;
    if (!GetModuleFileNameW(NULL, path, MAX_PATH)) return FALSE;
    WCHAR *file = wcsrchr(path, L'\\');
    return !_wcsicmp(file ? file + 1 : path, L"explorer.exe");
}
typedef struct {
    DWORD owner, epoch;
    FILETIME born;
    HMONITOR target;
    BOOL inside, done, dead, restoring, opening;
    HANDLE gate;
    LONG references;
} WindowState;

static HANDLE AcquireGate(DWORD owner, FILETIME born, DWORD epoch) {
    WCHAR name[128];
    swprintf(name, 128, PLACEMENT_MAPPING L".Gate.%lu.%08lx%08lx.%lu",
        owner, born.dwHighDateTime, born.dwLowDateTime, epoch);
    HANDLE gate = CreateMutexW(NULL, FALSE, name);
    if (!gate) return NULL;
    /* A dead application abandons the mutex instead of leaving a permanent count. */
    DWORD wait = WaitForSingleObject(gate, 0);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) return gate;
    CloseHandle(gate);
    return NULL;
}
static void ReleaseGate(HANDLE gate) {
    ReleaseMutex(gate);
    CloseHandle(gate);
}
static BOOL EnterGate(WindowState *state) {
    if (shared->blocked || (DWORD)(GateValue() >> 32) != state->epoch) return FALSE;
    HANDLE gate = AcquireGate(state->owner, state->born, state->epoch);
    if (!gate) return FALSE;
    /* Navigation or a controller restart may have won while opening the mutex. */
    if (shared->blocked || (DWORD)(GateValue() >> 32) != state->epoch) {
        ReleaseGate(gate);
        return FALSE;
    }
    state->gate = gate;
    return TRUE;
}
static void LeaveGate(WindowState *state) {
    if (!state->gate) return;
    /* Each show keeps its own handle, so an old callback cannot release a new gate. */
    ReleaseGate(state->gate);
    state->gate = NULL;
}

static LRESULT CALLBACK WindowProc(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
__declspec(dllexport) LRESULT CALLBACK PlacementHook(int, WPARAM, LPARAM);

static BOOL CALLBACK CountMonitor(HMONITOR monitor, HDC dc, LPRECT rect, LPARAM count) {
    (void)monitor; (void)dc; (void)rect;
    ++*(unsigned *)count;
    return TRUE;
}
static HMONITOR PendingTarget(HWND window) {
    DWORD_PTR reference = 0; DWORD pid = 0;
    if (GetWindowThreadProcessId(window, &pid) == GetCurrentThreadId() && pid == GetCurrentProcessId()
        && subclassApi.Get(window, WindowProc, (UINT_PTR)&PlacementHook, &reference)) {
        WindowState *state = (WindowState *)reference;
        if (!state->dead && state->opening && state->owner == shared->owner
            && SameTime(state->born, shared->born)) return state->target;
    }
    return NULL;
}
static HMONITOR Target(HWND window) {
    unsigned count = 0;
    if (!EnumDisplayMonitors(NULL, NULL, CountMonitor, (LPARAM)&count) || count < 2) return NULL;
    HWND root = NULL;
    for (HWND owner = GetWindow(window, GW_OWNER); owner; owner = GetWindow(owner, GW_OWNER))
        if (Ordinary(owner) && (IsWindowVisible(owner) || PendingTarget(owner))) root = owner;
    if (root) {
        HMONITOR pending = PendingTarget(root);
        if (pending) return pending;
        return MonitorFromWindow(root, MONITOR_DEFAULTTONEAREST);
    }
    POINT point;
    return GetCursorPos(&point) ? MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST) : NULL;
}

static void ReleaseState(WindowState *state) {
    if (!InterlockedDecrement(&state->references)) HeapFree(GetProcessHeap(), 0, state);
}
static void Finish(HWND window, UINT_PTR id, WindowState *state) {
    if (state->dead) return;
    state->dead = TRUE;
    subclassApi.Remove(window, WindowProc, id);
    LeaveGate(state);
    ReleaseState(state);
}

static BOOL Route(HWND window, WINDOWPOS *position, WindowState *state) {
    if (!Active() || shared->owner != state->owner || !SameTime(shared->born, state->born)
        || !Ordinary(window) || RunDialog(window)) return FALSE;
    if (!EnterGate(state) || !Active()) return FALSE;
    DWORD cloak = 0;
    /* Failed or shell-cloaked queries never authorize a move across desktops. */
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloak, sizeof(cloak))) || cloak)
        return FALSE;
    if (!state->target) state->target = Target(window);
    MONITORINFO target = {sizeof(target), {0}, {0}, 0};
    if (!state->target || !GetMonitorInfoW(state->target, &target)) return FALSE;
    RECT rect;
    if (!GetWindowRect(window, &rect)) return FALSE;
    LONG width = (position->flags & SWP_NOSIZE) ? rect.right - rect.left : position->cx;
    LONG height = (position->flags & SWP_NOSIZE) ? rect.bottom - rect.top : position->cy;
    if (!(position->flags & SWP_NOMOVE)) {
        rect.left = position->x; rect.top = position->y;
    }
    rect.right = rect.left + width; rect.bottom = rect.top + height;
    if (width <= 0 || height <= 0) return FALSE;
    HMONITOR from = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
    MONITORINFO source = {sizeof(source), {0}, {0}, 0};
    if (!from || !GetMonitorInfoW(from, &source)) return FALSE;
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if (!(style & WS_CAPTION) && rect.left <= source.rcMonitor.left && rect.top <= source.rcMonitor.top
        && rect.right >= source.rcMonitor.right && rect.bottom >= source.rcMonitor.bottom) return FALSE;
    if (from == state->target) return TRUE;
    LONG x = target.rcWork.left + rect.left - source.rcWork.left;
    LONG y = target.rcWork.top + rect.top - source.rcWork.top;
    x = max(target.rcWork.left, min(x, target.rcWork.right - width));
    y = max(target.rcWork.top, min(y, target.rcWork.bottom - height));
    if (style & WS_MAXIMIZE) {
        /* USER applies maximization against the new monitor's work area. */
        x = target.rcWork.left; y = target.rcWork.top;
        position->cx = target.rcWork.right - target.rcWork.left;
        position->cy = target.rcWork.bottom - target.rcWork.top;
        position->flags &= ~SWP_NOSIZE;
    }
    position->x = x; position->y = y; position->flags &= ~SWP_NOMOVE;
    InterlockedIncrement(&shared->placed);
    return TRUE;
}
static void RestoreBounds(HWND window, HMONITOR monitor) {
    WINDOWPLACEMENT placement = {0}; placement.length = sizeof(placement);
    MONITORINFO source = {sizeof(source), {0}, {0}, 0}, target = {sizeof(target), {0}, {0}, 0};
    if (!monitor || !GetWindowPlacement(window, &placement) || !GetMonitorInfoW(monitor, &target)) return;
    HMONITOR from = MonitorFromRect(&placement.rcNormalPosition, MONITOR_DEFAULTTONEAREST);
    if (!from || from == monitor || !GetMonitorInfoW(from, &source)) return;
    LONG width = placement.rcNormalPosition.right - placement.rcNormalPosition.left;
    LONG height = placement.rcNormalPosition.bottom - placement.rcNormalPosition.top;
    LONG x = placement.rcNormalPosition.left + target.rcMonitor.left - source.rcMonitor.left;
    LONG y = placement.rcNormalPosition.top + target.rcMonitor.top - source.rcMonitor.top;
    x = max(target.rcMonitor.left, min(x, target.rcMonitor.left + target.rcWork.right - target.rcWork.left - width));
    y = max(target.rcMonitor.top, min(y, target.rcMonitor.top + target.rcWork.bottom - target.rcWork.top - height));
    placement.rcNormalPosition = (RECT){x, y, x + width, y + height};
    /* Keep the current maximized state and leave the foreground window unchanged. */
    placement.showCmd = SW_SHOWNA;
    if (!SetWindowPlacement(window, &placement) && shared) InterlockedIncrement(&shared->failed);
}
static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR id, DWORD_PTR reference) {
    WindowState *state = (WindowState *)reference;
    InterlockedIncrement(&state->references);
    LRESULT result;
    if (message == WM_NCDESTROY) {
        Finish(window, id, state);
        result = subclassApi.Next(window, message, wparam, lparam);
        goto done;
    }
    if (message == WM_WINDOWPOSCHANGED && state->done && !state->restoring) {
        state->restoring = TRUE;
        if (IsZoomed(window) && Alive() && shared->enabled && shared->owner == state->owner
            && SameTime(shared->born, state->born)) RestoreBounds(window, state->target);
        state->restoring = FALSE;
        Finish(window, id, state);
    }
    if (message == WM_SHOWWINDOW && wparam) {
        state->opening = TRUE;
        if (Active()) state->target = Target(window);
    }
    if (message == WM_WINDOWPOSCHANGING && !state->done && !state->inside) {
        WINDOWPOS *position = (WINDOWPOS *)lparam;
        state->inside = TRUE;
        /* Let the app restore its saved geometry before adjusting the first show. */
        result = subclassApi.Next(window, message, wparam, lparam);
        state->inside = FALSE;
        if (!state->dead && (position->flags & SWP_SHOWWINDOW)) {
            state->done = TRUE;
            BOOL routed = Route(window, position, state);
            if (!routed && shared) InterlockedIncrement(&shared->skipped);
            if (routed) SetPropW(window, PLACEMENT_DONE, (HANDLE)(ULONG_PTR)1);
            if (!routed) Finish(window, id, state);
        }
        goto done;
    }
    result = subclassApi.Next(window, message, wparam, lparam);
done:
    ReleaseState(state);
    return result;
}
__declspec(dllexport) LRESULT CALLBACK PlacementHook(int code, WPARAM wparam, LPARAM lparam) {
    DWORD pid = 0;
    /* Mixed-bitness global hooks can call back on the installer thread. Never subclass a foreign HWND. */
    BOOL local = (code == HCBT_CREATEWND || code == HCBT_MINMAX)
        && GetWindowThreadProcessId((HWND)wparam, &pid) == GetCurrentThreadId() && pid == GetCurrentProcessId();
    if (local && Active() && shared->owner != GetCurrentProcessId() && !ShellProcess() && SubclassAvailable()) {
        HWND window = (HWND)wparam;
        DWORD_PTR reference = 0;
        if (code == HCBT_MINMAX && LOWORD(lparam) == SW_SHOWMAXIMIZED
            && subclassApi.Get(window, WindowProc, (UINT_PTR)&PlacementHook, &reference)) {
            WindowState *state = (WindowState *)reference;
            if (!state->done && !IsWindowVisible(window) && !IsZoomed(window)) {
                state->opening = TRUE;
                if (!state->target) state->target = Target(window);
                /* Relocate the hidden normal rectangle before USER chooses a maximization monitor. */
                WindowState before = *state;
                before.gate = NULL;
                WINDOWPOS position = {window, NULL, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER};
                if (Route(window, &position, &before) && !(position.flags & SWP_NOMOVE))
                    SetWindowPos(window, NULL, position.x, position.y, 0, 0,
                        SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
                LeaveGate(&before);
            }
        }
        if (code != HCBT_CREATEWND) return CallNextHookEx(NULL, code, wparam, lparam);
        CBT_CREATEWNDW *creation = (CBT_CREATEWNDW *)lparam;
        if (!(creation->lpcs->style & WS_CHILD) && Ordinary(window)
            && !subclassApi.Get(window, WindowProc, (UINT_PTR)&PlacementHook, &reference)) {
            WindowState *state = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*state));
            /* A pending hidden HWND may outlive the controller and its global hook. */
            if (state && (pinned || GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                | GET_MODULE_HANDLE_EX_FLAG_PIN, (LPCWSTR)(ULONG_PTR)&PlacementHook, &module))) {
                pinned = TRUE; state->owner = shared->owner; state->born = shared->born;
                state->epoch = (DWORD)(GateValue() >> 32);
                state->references = 1;
                if (subclassApi.Set(window, WindowProc, (UINT_PTR)&PlacementHook, (DWORD_PTR)state)) {
                    CREATESTRUCTW *parameters = creation->lpcs;
                    if ((parameters->style & WS_VISIBLE) && (parameters->style & WS_CAPTION)
                        && parameters->x != CW_USEDEFAULT && parameters->y != CW_USEDEFAULT
                        && parameters->cx > 0 && parameters->cy > 0) {
                        WindowState before = *state;
                        WINDOWPOS position = {window, NULL, parameters->x, parameters->y,
                            parameters->cx, parameters->cy, 0};
                        if (Route(window, &position, &before)) {
                            parameters->x = position.x; parameters->y = position.y;
                            state->target = before.target;
                        }
                        LeaveGate(&before);
                    }
                    state = NULL;
                } else InterlockedIncrement(&shared->failed);
            }
            if (state) HeapFree(GetProcessHeap(), 0, state);
        }
    }
    return CallNextHookEx(NULL, code, wparam, lparam);
}
static DWORD Install(void) {
    hook = SetWindowsHookExW(WH_CBT, PlacementHook, module, 0);
    return hook ? ERROR_SUCCESS : GetLastError();
}
__declspec(dllexport) void WINAPI PlacementStop(void);
__declspec(dllexport) DWORD WINAPI PlacementStart(void) {
    if (hook) return ERROR_ALREADY_INITIALIZED;
    HANDLE mutex = CreateMutexW(NULL, FALSE, PLACEMENT_MAPPING L".Controller");
    if (!mutex) return GetLastError();
    DWORD wait = WaitForSingleObject(mutex, 1000), error = ERROR_SUCCESS;
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) { CloseHandle(mutex); return ERROR_BUSY; }
    if (Alive() && shared->enabled) error = ERROR_ALREADY_EXISTS;
    if (!error) {
        if (!shared) {
            mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, sizeof(*shared), PLACEMENT_MAPPING);
            if (mapping) shared = MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, sizeof(*shared));
        }
        if (!shared) error = GetLastError();
        else {
            DWORD epoch = (DWORD)(GateValue() >> 32) + 1;
            if (!epoch) epoch = 1;
            /* A new epoch uses a separate mutex from pending old callbacks. */
            InterlockedExchange(&shared->enabled, FALSE);
            InterlockedExchange64(&shared->gates, (LONG64)((ULONGLONG)epoch << 32));
            shared->owner = 0;
            shared->blocked = FALSE;
            shared->host32 = shared->host32Error = shared->placed = shared->skipped = shared->failed = 0;
            shared->abi = PLACEMENT_ABI;
            FILETIME exit, kernel, user;
            if (!GetProcessTimes(GetCurrentProcess(), &shared->born, &exit, &kernel, &user)) error = GetLastError();
            else {
                shared->heartbeat = (LONG)GetTickCount();
                shared->owner = GetCurrentProcessId();
                controller = TRUE;
                InterlockedExchange(&shared->enabled, TRUE);
                error = Install();
                if (error) shared->enabled = FALSE;
            }
        }
    }
    ReleaseMutex(mutex); CloseHandle(mutex);
    if (error) PlacementStop();
    return error;
}
__declspec(dllexport) DWORD WINAPI PlacementJoin(void) {
    if (!Alive()) return ERROR_INVALID_OWNER;
    hostOwner = shared->owner; hostBorn = shared->born;
    hostEpoch = (DWORD)(GateValue() >> 32);
    DWORD error = Install();
    InterlockedExchange(&shared->host32Error, (LONG)error);
    if (!error) InterlockedExchange(&shared->host32, (LONG)GetCurrentProcessId());
    return error;
}
__declspec(dllexport) void WINAPI PlacementUpdate(BOOL blocked) {
    if (shared && shared->owner == GetCurrentProcessId()) {
        InterlockedExchange(&shared->blocked, blocked || navigationGate != NULL);
        InterlockedExchange(&shared->heartbeat, (LONG)GetTickCount());
    }
}
__declspec(dllexport) BOOL WINAPI PlacementBlock(BOOL block) {
    if (!shared || shared->owner != GetCurrentProcessId()) return FALSE;
    if (block) {
        if (navigationGate) return FALSE;
        InterlockedExchange(&shared->blocked, TRUE);
        /* Never wait for application code in a GUI callback. Retry on the next keypress. */
        navigationGate = AcquireGate(shared->owner, shared->born, (DWORD)(GateValue() >> 32));
        if (navigationGate) return TRUE;
        InterlockedExchange(&shared->blocked, FALSE);
        return FALSE;
    }
    if (navigationGate) {
        ReleaseGate(navigationGate);
        navigationGate = NULL;
    }
    InterlockedExchange(&shared->blocked, FALSE);
    return TRUE;
}
__declspec(dllexport) DWORD WINAPI PlacementStatus(DWORD index) {
    if (!shared || index > 4) return 0;
    volatile LONG *values[] = {&shared->host32, &shared->host32Error, &shared->placed, &shared->skipped, &shared->failed};
    return (DWORD)InterlockedCompareExchange(values[index], 0, 0);
}
__declspec(dllexport) BOOL WINAPI PlacementAlive(void) {
    return Alive() && shared->enabled && shared->owner == hostOwner && SameTime(shared->born, hostBorn)
        && (DWORD)(GateValue() >> 32) == hostEpoch;
}
__declspec(dllexport) void WINAPI PlacementStop(void) {
    if (controller && shared && shared->owner == GetCurrentProcessId()) InterlockedExchange(&shared->enabled, FALSE);
    if (hook) {
        if (!UnhookWindowsHookEx(hook)) {
            /* Keep any callback still registered by USER valid until this process exits. */
            GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                (LPCWSTR)(ULONG_PTR)&PlacementHook, &module);
        }
        hook = NULL;
    }
    if (navigationGate) { ReleaseGate(navigationGate); navigationGate = NULL; }
    if (ownerProcess) { CloseHandle(ownerProcess); ownerProcess = NULL; }
    if (shared) { UnmapViewOfFile(shared); shared = NULL; }
    if (mapping) { CloseHandle(mapping); mapping = NULL; }
    cachedOwner = 0;
    controller = FALSE; hostOwner = 0;
}
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) { module = instance; DisableThreadLibraryCalls(instance); }
    return TRUE;
}
