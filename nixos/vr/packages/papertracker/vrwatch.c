/* PaperTracker 在 Proton 下的 SteamVR 进程探测垫片。
 *
 * PaperTracker 用 Windows 进程列表（Toolhelp32）判断 SteamVR 是否在运行，并监视该进程退出；
 * Linux 原生的 vrserver 不在 wine 的进程表里，于是它永远认为 SteamVR 没开，也就不会去连
 * Proton 的 vrclient 桥。这里在 wine 里维护一个同名占位进程 vrserver.exe，跟随 Linux
 * vrserver 的生命周期启停；真正的 OpenVR 连接仍由 vrclient 桥转发到 Linux SteamVR。
 *
 * Proton 的 vrclient 桥只在进程启动时（umu.exe 调 vrclient_init_registry）初始化一次，结果记在易失键
 * HKCU\Software\Wine\VR 的 state 里；启动时 SteamVR 没开就是 -1，之后 VR_Init 一律 105
 * Interface Not Found，再调初始化也只会回"已初始化"。所以 Linux vrserver 出现时，若 state 不是 1，
 * 先删键重做一遍初始化，再放出占位进程让 PaperTracker 去连。
 *
 * 用法：vrwatch.exe <PaperTracker.exe> [参数...]
 *       vrserver.exe --placeholder      （由本程序自行拉起，只是睡眠）
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

static FILE *logf;

static void logmsg(const char *fmt, ...)
{
    va_list ap;
    SYSTEMTIME t;
    if (!logf) return;
    GetLocalTime(&t);
    fprintf(logf, "%02d:%02d:%02d.%03d ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_start(ap, fmt);
    vfprintf(logf, fmt, ap);
    va_end(ap);
    fputc('\n', logf);
    fflush(logf);
}

static BOOL comm_is_vrserver(const wchar_t *pid)
{
    wchar_t path[64];
    char buf[32] = {0};
    DWORD got = 0;
    HANDLE h;

    swprintf(path, 64, L"Z:\\proc\\%ls\\comm", pid);
    h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return FALSE;
    ReadFile(h, buf, sizeof(buf) - 1, &got, NULL);
    CloseHandle(h);
    return !strcmp(buf, "vrserver\n");
}

/* 找 Linux 上的 vrserver；先复查上次命中的 pid，省得每秒遍历整个 /proc */
static BOOL linux_vrserver_running(void)
{
    static wchar_t last[16];
    WIN32_FIND_DATAW fd;
    HANDLE find;
    BOOL found = FALSE;

    if (last[0] && comm_is_vrserver(last)) return TRUE;
    last[0] = 0;

    find = FindFirstFileW(L"Z:\\proc\\*", &fd);
    if (find == INVALID_HANDLE_VALUE) return FALSE;
    do
    {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (fd.cFileName[0] < L'0' || fd.cFileName[0] > L'9') continue;
        if (comm_is_vrserver(fd.cFileName))
        {
            wcsncpy(last, fd.cFileName, 15);
            found = TRUE;
            break;
        }
    } while (FindNextFileW(find, &fd));
    FindClose(find);
    return found;
}

static HANDLE spawn(const wchar_t *app, wchar_t *cmdline, const wchar_t *cwd)
{
    STARTUPINFOW si = {sizeof(si)};
    PROCESS_INFORMATION pi;

    if (!CreateProcessW(app, cmdline, NULL, NULL, FALSE, 0, NULL, cwd, &si, &pi))
    {
        logmsg("CreateProcess(%ls) failed: %lu", app, GetLastError());
        return NULL;
    }
    CloseHandle(pi.hThread);
    return pi.hProcess;
}

static DWORD vr_state(void)
{
    DWORD value = (DWORD)-2, size = sizeof(value);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Wine\\VR", L"state", RRF_RT_REG_DWORD, NULL, &value, &size);
    return value;
}

/* 与 Proton 的 steam.exe/umu.exe 相同：调 vrclient_x64.dll 导出的 vrclient_init_registry */
static void ensure_vr_registry(void)
{
    BOOL (CDECL *init)(void);
    HMODULE vrclient;
    DWORD before = vr_state(), state;
    int i;

    /* 0 = umu.exe 的初始化还在跑：等它跑完，中途删键会让正在等这个键的 DXVK/vkd3d 永远卡住 */
    for (i = 0; i < 150 && before == 0; i++)
    {
        Sleep(100);
        before = vr_state();
    }
    if (before == 1) return;
    RegDeleteTreeW(HKEY_CURRENT_USER, L"Software\\Wine\\VR");
    if (!(vrclient = LoadLibraryW(L"vrclient_x64")))
    {
        logmsg("cannot load vrclient_x64: %lu", GetLastError());
        return;
    }
    if ((init = (void *)GetProcAddress(vrclient, "vrclient_init_registry"))) init();
    else logmsg("vrclient_init_registry export missing");
    FreeLibrary(vrclient);

    /* 初始化在后台线程里跑，state 从 0 变成 1 / -1 */
    for (i = 0; i < 150 && (state = vr_state()) == 0; i++) Sleep(100);
    logmsg("VR registry re-initialized: state %ld -> %ld", (long)before, (long)state);
}

/* PaperTracker 自带的"重启 SteamVR"命令同时点名这三个进程，探测时用的也是它们 */
static const wchar_t *names[] = {L"vrserver.exe", L"vrmonitor.exe", L"vrcompositor.exe"};
#define NNAMES (sizeof(names) / sizeof(names[0]))

int wmain(int argc, wchar_t **argv)
{
    wchar_t self[MAX_PATH], dir[MAX_PATH], path[NNAMES][MAX_PATH], logpath[MAX_PATH], appdir[MAX_PATH], *p, *cmdline;
    HANDLE app, dummy[NNAMES] = {0};
    BOOL was_running = FALSE;
    DWORD code = 0;
    UINT i;

    if (argc > 1 && !wcscmp(argv[1], L"--placeholder"))
    {
        Sleep(INFINITE);
        return 0;
    }
    if (argc < 2)
    {
        fwprintf(stderr, L"usage: vrwatch.exe <PaperTracker.exe> [args...]\n");
        return 2;
    }

    /* 占位进程和日志都放在本程序旁边 */
    GetModuleFileNameW(NULL, self, MAX_PATH);
    wcscpy(dir, self);
    if ((p = wcsrchr(dir, L'\\'))) p[1] = 0;
    wcscpy(logpath, dir);
    wcscat(logpath, L"vrwatch.log");
    logf = _wfopen(logpath, L"w");
    for (i = 0; i < NNAMES; i++)
    {
        wcscpy(path[i], dir);
        wcscat(path[i], names[i]);
        if (!CopyFileW(self, path[i], FALSE) && GetFileAttributesW(path[i]) == INVALID_FILE_ATTRIBUTES)
            logmsg("cannot create placeholder %ls: %lu", path[i], GetLastError());
    }

    /* 原样把 vrwatch.exe 之后的命令行交给 PaperTracker */
    cmdline = GetCommandLineW();
    if (*cmdline == L'"') cmdline = wcschr(cmdline + 1, L'"') + 1;
    else while (*cmdline && *cmdline != L' ') cmdline++;
    while (*cmdline == L' ') cmdline++;
    cmdline = _wcsdup(cmdline);

    /* PaperTracker 的配置用相对路径，工作目录必须是它的安装目录 */
    wcscpy(appdir, argv[1]);
    if ((p = wcsrchr(appdir, L'\\'))) *p = 0;

    if (!(app = spawn(argv[1], cmdline, appdir))) return 1;
    logmsg("started %ls", argv[1]);

    while (WaitForSingleObject(app, 1000) == WAIT_TIMEOUT)
    {
        BOOL running = linux_vrserver_running();

        if (running != was_running)
        {
            if (running) ensure_vr_registry();
            logmsg(running ? "linux vrserver up -> placeholders on" : "linux vrserver gone -> placeholders off");
        }
        was_running = running;

        for (i = 0; i < NNAMES; i++)
        {
            if (dummy[i] && WaitForSingleObject(dummy[i], 0) == WAIT_OBJECT_0)
            {
                logmsg("placeholder %ls was terminated externally", names[i]);
                CloseHandle(dummy[i]);
                dummy[i] = NULL;
            }
            if (running && !dummy[i])
            {
                wchar_t args[64];
                swprintf(args, 64, L"%ls --placeholder", names[i]);
                dummy[i] = spawn(path[i], args, NULL);
            }
            else if (!running && dummy[i])
            {
                TerminateProcess(dummy[i], 0);
                CloseHandle(dummy[i]);
                dummy[i] = NULL;
            }
        }
    }

    GetExitCodeProcess(app, &code);
    for (i = 0; i < NNAMES; i++)
        if (dummy[i]) TerminateProcess(dummy[i], 0);
    logmsg("PaperTracker exited with %lu", code);
    return (int)code;
}
