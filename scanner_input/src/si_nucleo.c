// Núcleo comum: lista de aparelhos, classificação e fila de teclas.
#include <ctype.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "si_interno.h"

// ---------------------------------------------------------------------------
// Parâmetros da classificação por comportamento
// ---------------------------------------------------------------------------
#define RAJADA_MIN_TECLAS 6        // mínimo de caracteres antes do Enter
#define RAPIDO_MEDIA_MS 35.0       // rajada rápida: média entre teclas
#define RAPIDO_MAX_MS 100.0        //                e maior intervalo
#define REGULAR_MIN_TECLAS 8       // rajada regular (scanner lento)
#define REGULAR_MEDIA_MAX_MS 150.0
#define REGULAR_CV_MAX 0.20        // desvio padrão / média
#define PAUSA_REINICIA_MS 1000     // pausa maior que isso começa nova rajada

#define FILA_VALIDADE_US 1500000   // tecla não consultada some depois disso
#define ESPERA_MAX_MS 50           // tempo que a consulta espera a lib ver a tecla

#define MAX_APARELHOS 64
#define MAX_FILA 512
#define MAX_APRENDIDOS 64

// Fabricantes de scanner (USB VID).
static const struct { int vid; const char* nome; } FABRICANTES[] = {
    {0x0C2E, "Honeywell/Metrologic"},
    {0x0536, "Hand Held Products"},
    {0x05E0, "Symbol/Zebra"},
    {0x05F9, "Datalogic (PSC)"},
    {0x080C, "Datalogic"},
    {0x1EAB, "Newland"},
    {0x065A, "Opticon"},
};

// Trechos de nome que indicam scanner (comparação sem maiúsculas).
static const char* NOMES[] = {
    "barcode", "bar code", "scanner", "scan", "hid kbw", "leitor",
    "honeywell", "metrologic", "symbol", "zebra", "datalogic", "newland",
    "opticon", "elgin", "bematech", "tanca", "zebex", "cipherlab",
};

// ---------------------------------------------------------------------------
// Estado
// ---------------------------------------------------------------------------
typedef struct {
  SiAparelho info;
  char chave[256];
  // rajada em andamento
  int64_t ultima_us;
  int teclas;
  double soma_ms, soma2_ms, max_ms;
} Aparelho;

typedef struct {
  uint32_t hid;
  int aparelho;
  int64_t t_us;
} Tecla;

static Aparelho g_aparelhos[MAX_APARELHOS];
static int g_n_aparelhos;
static Tecla g_fila[MAX_FILA];
static int g_n_fila;
static char g_aprendidos[MAX_APRENDIDOS][160];
static int g_n_aprendidos;
static char g_arquivo[1024];
static char g_diag[512];
static int g_ativo;

// ---------------------------------------------------------------------------
// Tabela evdev -> USB HID usage (página 0x07)
// ---------------------------------------------------------------------------
static uint32_t evdev_para_hid(int c) {
  static const uint8_t t[128] = {
      [1] = 0x29,  [2] = 0x1E,  [3] = 0x1F,  [4] = 0x20,  [5] = 0x21,
      [6] = 0x22,  [7] = 0x23,  [8] = 0x24,  [9] = 0x25,  [10] = 0x26,
      [11] = 0x27, [12] = 0x2D, [13] = 0x2E, [14] = 0x2A, [15] = 0x2B,
      [16] = 0x14, [17] = 0x1A, [18] = 0x08, [19] = 0x15, [20] = 0x17,
      [21] = 0x1C, [22] = 0x18, [23] = 0x0C, [24] = 0x12, [25] = 0x13,
      [26] = 0x2F, [27] = 0x30, [28] = 0x28, [29] = 0xE0, [30] = 0x04,
      [31] = 0x16, [32] = 0x07, [33] = 0x09, [34] = 0x0A, [35] = 0x0B,
      [36] = 0x0D, [37] = 0x0E, [38] = 0x0F, [39] = 0x33, [40] = 0x34,
      [41] = 0x35, [42] = 0xE1, [43] = 0x31, [44] = 0x1D, [45] = 0x1B,
      [46] = 0x06, [47] = 0x19, [48] = 0x05, [49] = 0x11, [50] = 0x10,
      [51] = 0x36, [52] = 0x37, [53] = 0x38, [54] = 0xE5, [55] = 0x55,
      [56] = 0xE2, [57] = 0x2C, [58] = 0x39, [59] = 0x3A, [60] = 0x3B,
      [61] = 0x3C, [62] = 0x3D, [63] = 0x3E, [64] = 0x3F, [65] = 0x40,
      [66] = 0x41, [67] = 0x42, [68] = 0x43, [69] = 0x53, [70] = 0x47,
      [71] = 0x5F, [72] = 0x60, [73] = 0x61, [74] = 0x56, [75] = 0x5C,
      [76] = 0x5D, [77] = 0x5E, [78] = 0x57, [79] = 0x59, [80] = 0x5A,
      [81] = 0x5B, [82] = 0x62, [83] = 0x63, [86] = 0x64, [87] = 0x44,
      [88] = 0x45, [89] = 0x87, [96] = 0x58, [97] = 0xE4, [98] = 0x54,
      [99] = 0x46, [100] = 0xE6, [102] = 0x4A, [103] = 0x52, [104] = 0x4B,
      [105] = 0x50, [106] = 0x4F, [107] = 0x4D, [108] = 0x51, [109] = 0x4E,
      [110] = 0x49, [111] = 0x4C, [117] = 0x67, [119] = 0x48, [121] = 0x85,
      [125] = 0xE3, [126] = 0xE7, [127] = 0x65,
  };
  if (c < 0 || c >= 128) return 0;
  return t[c];
}

int si_scancode_para_evdev(int sc, int e0) {
  if (!e0) {
    if (sc >= 1 && sc <= 88) return sc;  // set 1 == evdev nessa faixa
    if (sc == 0x73) return 89;           // ABNT2 "/?"
    if (sc == 0x7E) return 121;          // ABNT2 ponto do teclado numérico
    return 0;
  }
  switch (sc) {
    case 0x1C: return 96;   // Enter numérico
    case 0x1D: return 97;   // Ctrl direito
    case 0x35: return 98;   // / numérico
    case 0x37: return 99;   // Print Screen
    case 0x38: return 100;  // Alt direito
    case 0x47: return 102;  // Home
    case 0x48: return 103;  // Cima
    case 0x49: return 104;  // Page Up
    case 0x4B: return 105;  // Esquerda
    case 0x4D: return 106;  // Direita
    case 0x4F: return 107;  // End
    case 0x50: return 108;  // Baixo
    case 0x51: return 109;  // Page Down
    case 0x52: return 110;  // Insert
    case 0x53: return 111;  // Delete
    case 0x5B: return 125;  // Windows esquerdo
    case 0x5C: return 126;  // Windows direito
    case 0x5D: return 127;  // Menu
  }
  return 0;
}

static int eh_modificador(uint32_t hid) { return hid >= 0xE0 || hid == 0x39; }
static int eh_enter(uint32_t hid) { return hid == 0x28 || hid == 0x58; }

// ---------------------------------------------------------------------------
// Aprendidos (arquivo de estado: uma chave por linha)
// ---------------------------------------------------------------------------
static void chave_aprendizado(const SiAparelho* a, char* out, size_t n) {
  if (a->vid || a->pid)
    snprintf(out, n, "%04x:%04x", a->vid, a->pid);
  else
    snprintf(out, n, "nome:%s", a->nome);
}

static int foi_aprendido(const SiAparelho* a) {
  char k[160];
  chave_aprendizado(a, k, sizeof k);
  for (int i = 0; i < g_n_aprendidos; i++)
    if (strcmp(g_aprendidos[i], k) == 0) return 1;
  return 0;
}

static void gravar_aprendidos(void) {
  if (!g_arquivo[0]) return;
  FILE* f = fopen(g_arquivo, "w");
  if (!f) {
    snprintf(g_diag, sizeof g_diag, "não foi possível gravar %s", g_arquivo);
    return;
  }
  for (int i = 0; i < g_n_aprendidos; i++) fprintf(f, "%s\n", g_aprendidos[i]);
  fclose(f);
}

static void carregar_aprendidos(void) {
  g_n_aprendidos = 0;
  if (!g_arquivo[0]) return;
  FILE* f = fopen(g_arquivo, "r");
  if (!f) return;
  char linha[160];
  while (g_n_aprendidos < MAX_APRENDIDOS && fgets(linha, sizeof linha, f)) {
    linha[strcspn(linha, "\r\n")] = 0;
    if (linha[0]) strcpy(g_aprendidos[g_n_aprendidos++], linha);
  }
  fclose(f);
}

static void aprender(Aparelho* a, int motivo) {
  a->info.tipo = SI_SCANNER;
  a->info.motivo = motivo;
  if (foi_aprendido(&a->info) || g_n_aprendidos >= MAX_APRENDIDOS) return;
  chave_aprendizado(&a->info, g_aprendidos[g_n_aprendidos++], 160);
  gravar_aprendidos();
}

// ---------------------------------------------------------------------------
// Classificação pelos dados do aparelho
// ---------------------------------------------------------------------------
static int contem_sem_caixa(const char* texto, const char* trecho) {
  size_t n = strlen(trecho);
  for (; *texto; texto++) {
    size_t i = 0;
    while (i < n && texto[i] &&
           tolower((unsigned char)texto[i]) == tolower((unsigned char)trecho[i]))
      i++;
    if (i == n) return 1;
  }
  return 0;
}

static void classificar_por_dados(Aparelho* a) {
  a->info.tipo = SI_TECLADO;
  a->info.motivo = SI_MOTIVO_NENHUM;
  for (size_t i = 0; i < sizeof FABRICANTES / sizeof *FABRICANTES; i++)
    if (a->info.vid == FABRICANTES[i].vid) {
      a->info.tipo = SI_SCANNER;
      a->info.motivo = SI_MOTIVO_FABRICANTE;
      return;
    }
  for (size_t i = 0; i < sizeof NOMES / sizeof *NOMES; i++)
    if (contem_sem_caixa(a->info.nome, NOMES[i])) {
      a->info.tipo = SI_SCANNER;
      a->info.motivo = SI_MOTIVO_NOME;
      return;
    }
  if (foi_aprendido(&a->info)) {
    a->info.tipo = SI_SCANNER;
    a->info.motivo = SI_MOTIVO_APRENDIDO;
  }
}

// ---------------------------------------------------------------------------
// Classificação por comportamento (rajada de cada aparelho)
// ---------------------------------------------------------------------------
static void zerar_rajada(Aparelho* a) {
  a->ultima_us = 0;
  a->teclas = 0;
  a->soma_ms = a->soma2_ms = a->max_ms = 0;
}

static void avaliar_rajada(Aparelho* a) {
  int intervalos = a->teclas - 1;
  if (a->info.tipo == SI_SCANNER || a->info.motivo == SI_MOTIVO_SEM_APARELHO ||
      intervalos < 1)
    return;
  double media = a->soma_ms / intervalos;
  double var = a->soma2_ms / intervalos - media * media;
  double cv = media > 0 ? sqrt(var > 0 ? var : 0) / media : 0;

  if (a->teclas >= RAJADA_MIN_TECLAS && media <= RAPIDO_MEDIA_MS &&
      a->max_ms <= RAPIDO_MAX_MS)
    aprender(a, SI_MOTIVO_VELOCIDADE);
  else if (a->teclas >= REGULAR_MIN_TECLAS && media <= REGULAR_MEDIA_MAX_MS &&
           cv <= REGULAR_CV_MAX)
    aprender(a, SI_MOTIVO_REGULARIDADE);
}

static void registrar_na_rajada(Aparelho* a, uint32_t hid, int64_t t_us) {
  if (eh_modificador(hid)) return;  // Shift do scanner não conta
  if (eh_enter(hid)) {
    avaliar_rajada(a);
    zerar_rajada(a);
    return;
  }
  if (a->ultima_us) {
    double ms = (double)(t_us - a->ultima_us) / 1000.0;
    if (ms > PAUSA_REINICIA_MS) {
      zerar_rajada(a);
    } else {
      a->soma_ms += ms;
      a->soma2_ms += ms * ms;
      if (ms > a->max_ms) a->max_ms = ms;
    }
  }
  a->ultima_us = t_us;
  a->teclas++;
}

// ---------------------------------------------------------------------------
// Entrada vinda da parte do sistema
// ---------------------------------------------------------------------------
int nucleo_aparelho_conectado(const char* chave, const char* nome, int vid,
                              int pid, int sem_aparelho) {
  plat_travar();
  Aparelho* a = NULL;
  for (int i = 0; i < g_n_aparelhos; i++)
    if (strcmp(g_aparelhos[i].chave, chave) == 0) a = &g_aparelhos[i];
  if (!a && g_n_aparelhos < MAX_APARELHOS) {
    a = &g_aparelhos[g_n_aparelhos];
    memset(a, 0, sizeof *a);
    a->info.id = g_n_aparelhos++;
    snprintf(a->chave, sizeof a->chave, "%s", chave);
  }
  int id = -1;
  if (a) {
    snprintf(a->info.nome, sizeof a->info.nome, "%s", nome ? nome : "");
    snprintf(a->info.caminho, sizeof a->info.caminho, "%s", chave);
    a->info.vid = vid;
    a->info.pid = pid;
    a->info.conectado = 1;
    zerar_rajada(a);
    if (sem_aparelho) {
      a->info.tipo = SI_TECLADO;
      a->info.motivo = SI_MOTIVO_SEM_APARELHO;
    } else {
      classificar_por_dados(a);
    }
    id = a->info.id;
  }
  plat_destravar();
  return id;
}

void nucleo_aparelho_desconectado(const char* chave) {
  plat_travar();
  for (int i = 0; i < g_n_aparelhos; i++)
    if (strcmp(g_aparelhos[i].chave, chave) == 0)
      g_aparelhos[i].info.conectado = 0;
  plat_destravar();
}

void nucleo_tecla(int aparelho, int codigo, int64_t t_us) {
  uint32_t hid = evdev_para_hid(codigo);
  if (!hid) return;
  plat_travar();
  if (aparelho >= 0 && aparelho < g_n_aparelhos)
    registrar_na_rajada(&g_aparelhos[aparelho], hid, t_us);
  if (g_n_fila == MAX_FILA) {  // cheia: descarta a mais antiga
    memmove(g_fila, g_fila + 1, sizeof(Tecla) * (MAX_FILA - 1));
    g_n_fila--;
  }
  g_fila[g_n_fila].hid = hid;
  g_fila[g_n_fila].aparelho = aparelho;
  g_fila[g_n_fila].t_us = plat_agora_us();
  g_n_fila++;
  plat_sinalizar();
  plat_destravar();
}

void nucleo_diagnostico(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  plat_travar();
  vsnprintf(g_diag, sizeof g_diag, fmt, ap);
  plat_destravar();
  va_end(ap);
}

// ---------------------------------------------------------------------------
// API exportada
// ---------------------------------------------------------------------------
SI_EXPORT int32_t si_iniciar(const char* arquivo_estado) {
  if (g_ativo) return 0;
  snprintf(g_arquivo, sizeof g_arquivo, "%s", arquivo_estado ? arquivo_estado : "");
  carregar_aprendidos();
  g_n_aparelhos = 0;
  g_n_fila = 0;
  g_diag[0] = 0;
  int r = plat_iniciar();
  if (r == 0) g_ativo = 1;
  return r;
}

SI_EXPORT void si_parar(void) {
  if (!g_ativo) return;
  plat_parar();
  g_ativo = 0;
}

static void expirar_fila(int64_t agora) {
  int j = 0;
  for (int i = 0; i < g_n_fila; i++)
    if (agora - g_fila[i].t_us <= FILA_VALIDADE_US) g_fila[j++] = g_fila[i];
  g_n_fila = j;
}

SI_EXPORT SiOrigem si_origem_da_tecla(uint32_t hid_usage) {
  SiOrigem r = {SI_DESCONHECIDO, -1};
  uint32_t hid = hid_usage & 0xFFFF;
  if (!g_ativo || !hid) return r;
  int64_t inicio = plat_agora_us();
  plat_travar();
  for (;;) {
    int64_t agora = plat_agora_us();
    expirar_fila(agora);
    int achou = -1;
    for (int i = 0; i < g_n_fila; i++)
      if (g_fila[i].hid == hid) { achou = i; break; }  // a mais antiga
    if (achou >= 0) {
      int ap = g_fila[achou].aparelho;
      memmove(g_fila + achou, g_fila + achou + 1,
              sizeof(Tecla) * (g_n_fila - achou - 1));
      g_n_fila--;
      r.aparelho = ap;
      r.tipo = (ap >= 0 && ap < g_n_aparelhos) ? g_aparelhos[ap].info.tipo
                                               : SI_TECLADO;
      break;
    }
    // A tecla pode chegar ao app antes de a lib vê-la: espera um pouco.
    if (agora - inicio >= ESPERA_MAX_MS * 1000) break;
    plat_aguardar(5);
  }
  plat_destravar();
  return r;
}

SI_EXPORT int32_t si_aparelhos(SiAparelho* saida, int32_t max) {
  plat_travar();
  int n = 0;
  for (int i = 0; i < g_n_aparelhos && n < max; i++)
    saida[n++] = g_aparelhos[i].info;
  plat_destravar();
  return n;
}

SI_EXPORT void si_esquecer_aprendidos(void) {
  plat_travar();
  g_n_aprendidos = 0;
  gravar_aprendidos();
  for (int i = 0; i < g_n_aparelhos; i++) {
    int m = g_aparelhos[i].info.motivo;
    if (m == SI_MOTIVO_APRENDIDO || m == SI_MOTIVO_VELOCIDADE ||
        m == SI_MOTIVO_REGULARIDADE) {
      g_aparelhos[i].info.tipo = SI_TECLADO;
      g_aparelhos[i].info.motivo = SI_MOTIVO_NENHUM;
    }
  }
  plat_destravar();
}

SI_EXPORT const char* si_diagnostico(void) { return g_diag; }
