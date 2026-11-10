// Windows: Raw Input numa janela invisível da própria lib (thread própria).
// Só observa: não filtra nem altera mensagens do app.
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <hidsdi.h>
#include <stdio.h>
#include <string.h>

#include "si_interno.h"

static CRITICAL_SECTION g_cs;
static CONDITION_VARIABLE g_cv;
static HANDLE g_thread;
static DWORD g_thread_id;
static HANDLE g_pronto;
static int g_resultado;
static LARGE_INTEGER g_freq;

#define MAX_DISP 64
static struct {
  HANDLE h;
  int id;
  char caminho[256];
} g_disp[MAX_DISP];
static int g_n_disp;
static int g_id_injetado = -1;

void plat_travar(void) { EnterCriticalSection(&g_cs); }
void plat_destravar(void) { LeaveCriticalSection(&g_cs); }
void plat_sinalizar(void) { WakeAllConditionVariable(&g_cv); }
void plat_aguardar(int ms) { SleepConditionVariableCS(&g_cv, &g_cs, (DWORD)ms); }

int64_t plat_agora_us(void) {
  LARGE_INTEGER c;
  QueryPerformanceCounter(&c);
  return (int64_t)(c.QuadPart * 1000000 / g_freq.QuadPart);
}

static int hex(const char* s, const char* marca) {
  const char* p = strstr(s, marca);
  if (!p) return 0;
  unsigned v = 0;
  sscanf(p + strlen(marca), "%4x", &v);
  return (int)v;
}

static void caminho_de(HANDLE h, char* out, size_t n) {
  out[0] = 0;
  UINT tam = 0;
  GetRawInputDeviceInfoA(h, RIDI_DEVICENAME, NULL, &tam);
  if (tam == 0 || tam >= n) return;
  GetRawInputDeviceInfoA(h, RIDI_DEVICENAME, out, &tam);
}

// Nome do produto/fabricante pelo HID (alguns aparelhos negam; tudo bem).
static void nome_de(const char* caminho, char* out, size_t n) {
  out[0] = 0;
  HANDLE f = CreateFileA(caminho, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                         OPEN_EXISTING, 0, NULL);
  if (f == INVALID_HANDLE_VALUE) return;
  WCHAR fab[64] = L"", prod[64] = L"";
  HidD_GetManufacturerString(f, fab, sizeof fab);
  HidD_GetProductString(f, prod, sizeof prod);
  CloseHandle(f);
  WCHAR junto[140];
  _snwprintf(junto, 140, L"%s%s%s", fab, (fab[0] && prod[0]) ? L" " : L"", prod);
  junto[139] = 0;
  WideCharToMultiByte(CP_UTF8, 0, junto, -1, out, (int)n, NULL, NULL);
}

static int registrar(HANDLE h) {
  for (int i = 0; i < g_n_disp; i++)
    if (g_disp[i].h == h) return g_disp[i].id;
  if (h == NULL) {  // tecla injetada (SendInput, AnyDesk, RDP...)
    if (g_id_injetado < 0)
      g_id_injetado = nucleo_aparelho_conectado("(sem aparelho)",
                                                "Teclas injetadas (sem aparelho físico)",
                                                0, 0, 1);
    return g_id_injetado;
  }
  RID_DEVICE_INFO info = {sizeof info};
  UINT tam = sizeof info;
  if (GetRawInputDeviceInfoA(h, RIDI_DEVICEINFO, &info, &tam) == (UINT)-1 ||
      info.dwType != RIM_TYPEKEYBOARD)
    return -1;
  char caminho[256], nome[128];
  caminho_de(h, caminho, sizeof caminho);
  nome_de(caminho, nome, sizeof nome);
  int id = nucleo_aparelho_conectado(caminho[0] ? caminho : "(desconhecido)", nome,
                                     hex(caminho, "VID_"), hex(caminho, "PID_"), 0);
  if (g_n_disp < MAX_DISP) {
    g_disp[g_n_disp].h = h;
    g_disp[g_n_disp].id = id;
    snprintf(g_disp[g_n_disp].caminho, sizeof g_disp[0].caminho, "%s", caminho);
    g_n_disp++;
  }
  return id;
}

static void remover(HANDLE h) {
  for (int i = 0; i < g_n_disp; i++)
    if (g_disp[i].h == h) {
      if (g_disp[i].caminho[0]) nucleo_aparelho_desconectado(g_disp[i].caminho);
      g_disp[i] = g_disp[--g_n_disp];
      return;
    }
}

static void listar_existentes(void) {
  UINT n = 0;
  GetRawInputDeviceList(NULL, &n, sizeof(RAWINPUTDEVICELIST));
  if (n == 0) return;
  RAWINPUTDEVICELIST lista[MAX_DISP];
  if (n > MAX_DISP) n = MAX_DISP;
  n = GetRawInputDeviceList(lista, &n, sizeof(RAWINPUTDEVICELIST));
  if (n == (UINT)-1) return;
  for (UINT i = 0; i < n; i++)
    if (lista[i].dwType == RIM_TYPEKEYBOARD) registrar(lista[i].hDevice);
}

static LRESULT CALLBACK proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_INPUT) {
    BYTE buf[sizeof(RAWINPUT) + 64];
    UINT tam = sizeof buf;
    if (GetRawInputData((HRAWINPUT)lp, RID_INPUT, buf, &tam, sizeof(RAWINPUTHEADER)) !=
        (UINT)-1) {
      RAWINPUT* ri = (RAWINPUT*)buf;
      if (ri->header.dwType == RIM_TYPEKEYBOARD) {
        RAWKEYBOARD* k = &ri->data.keyboard;
        if (!(k->Flags & RI_KEY_BREAK) && k->MakeCode != 0) {
          int codigo = si_scancode_para_evdev(k->MakeCode, (k->Flags & RI_KEY_E0) != 0);
          if (codigo) nucleo_tecla(registrar(ri->header.hDevice), codigo, plat_agora_us());
        }
      }
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
  }
  if (msg == WM_INPUT_DEVICE_CHANGE) {
    if (wp == GIDC_ARRIVAL) registrar((HANDLE)lp);
    else if (wp == GIDC_REMOVAL) remover((HANDLE)lp);
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

static DWORD WINAPI laco(LPVOID arg) {
  (void)arg;
  WNDCLASSW wc = {0};
  wc.lpfnWndProc = proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = L"scanner_input_janela";
  RegisterClassW(&wc);
  HWND hwnd = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                              NULL, wc.hInstance, NULL);
  RAWINPUTDEVICE rid = {0x01, 0x06, RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, hwnd};
  if (!hwnd || !RegisterRawInputDevices(&rid, 1, sizeof rid)) {
    nucleo_diagnostico("Falha ao registrar Raw Input (erro %lu)", GetLastError());
    g_resultado = -3;
    SetEvent(g_pronto);
    return 0;
  }
  listar_existentes();
  g_resultado = 0;
  SetEvent(g_pronto);

  MSG m;
  while (GetMessageW(&m, NULL, 0, 0) > 0) {
    TranslateMessage(&m);
    DispatchMessageW(&m);
  }
  rid.dwFlags = RIDEV_REMOVE;
  rid.hwndTarget = NULL;
  RegisterRawInputDevices(&rid, 1, sizeof rid);
  DestroyWindow(hwnd);
  return 0;
}

int plat_iniciar(void) {
  static int inicializado = 0;
  if (!inicializado) {
    InitializeCriticalSection(&g_cs);
    InitializeConditionVariable(&g_cv);
    QueryPerformanceFrequency(&g_freq);
    inicializado = 1;
  }
  g_n_disp = 0;
  g_id_injetado = -1;
  g_pronto = CreateEventW(NULL, TRUE, FALSE, NULL);
  g_thread = CreateThread(NULL, 0, laco, NULL, 0, &g_thread_id);
  if (!g_thread) return -1;
  WaitForSingleObject(g_pronto, INFINITE);
  CloseHandle(g_pronto);
  return g_resultado;
}

void plat_parar(void) {
  PostThreadMessageW(g_thread_id, WM_QUIT, 0, 0);
  WaitForSingleObject(g_thread, 5000);
  CloseHandle(g_thread);
}
