// Linux: lê /dev/input/event* (evdev) sem EVIOCGRAB — só observa.
// Precisa de permissão de leitura nos eventos (grupo "input" ou regra udev).
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "si_interno.h"

#define MAX_FDS 64
#define REVARRER_MS 2000  // procura aparelhos novos/removidos

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cond;
static pthread_t g_thread;
static int g_pipe[2] = {-1, -1};

typedef struct {
  int fd;
  int id;
  char caminho[64];
} Fonte;
static Fonte g_fontes[MAX_FDS];
static int g_n_fontes;

void plat_travar(void) { pthread_mutex_lock(&g_mutex); }
void plat_destravar(void) { pthread_mutex_unlock(&g_mutex); }
void plat_sinalizar(void) { pthread_cond_broadcast(&g_cond); }

int64_t plat_agora_us(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

void plat_aguardar(int ms) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  ts.tv_nsec += (long)ms * 1000000;
  ts.tv_sec += ts.tv_nsec / 1000000000;
  ts.tv_nsec %= 1000000000;
  pthread_cond_timedwait(&g_cond, &g_mutex, &ts);
}

#define BIT(arr, n) ((arr[(n) / (8 * sizeof(long))] >> ((n) % (8 * sizeof(long)))) & 1)

// Só interessa aparelho que tem teclas de letra ou número.
static int parece_teclado(int fd) {
  unsigned long ev[(EV_MAX + 8 * sizeof(long)) / (8 * sizeof(long))] = {0};
  unsigned long keys[(KEY_MAX + 8 * sizeof(long)) / (8 * sizeof(long))] = {0};
  if (ioctl(fd, EVIOCGBIT(0, sizeof ev), ev) < 0 || !BIT(ev, EV_KEY)) return 0;
  if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof keys), keys) < 0) return 0;
  return BIT(keys, KEY_1) || BIT(keys, KEY_A) || BIT(keys, KEY_KP1);
}

static void fechar_fonte(int i) {
  close(g_fontes[i].fd);
  nucleo_aparelho_desconectado(g_fontes[i].caminho);
  g_fontes[i] = g_fontes[--g_n_fontes];
}

static void varrer(void) {
  // remove os que sumiram
  for (int i = g_n_fontes - 1; i >= 0; i--)
    if (access(g_fontes[i].caminho, F_OK) != 0) fechar_fonte(i);

  DIR* d = opendir("/dev/input");
  if (!d) return;
  int negados = 0;
  struct dirent* e;
  while ((e = readdir(d)) && g_n_fontes < MAX_FDS) {
    if (strncmp(e->d_name, "event", 5) != 0) continue;
    char caminho[64];
    snprintf(caminho, sizeof caminho, "/dev/input/%s", e->d_name);
    int ja = 0;
    for (int i = 0; i < g_n_fontes; i++)
      if (strcmp(g_fontes[i].caminho, caminho) == 0) ja = 1;
    if (ja) continue;

    int fd = open(caminho, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
      if (errno == EACCES) negados++;
      continue;
    }
    if (!parece_teclado(fd)) {
      close(fd);
      continue;
    }
    char nome[128] = "";
    struct input_id id = {0};
    ioctl(fd, EVIOCGNAME(sizeof nome), nome);
    ioctl(fd, EVIOCGID, &id);
    int ap = nucleo_aparelho_conectado(caminho, nome, id.vendor, id.product, 0);
    g_fontes[g_n_fontes].fd = fd;
    g_fontes[g_n_fontes].id = ap;
    snprintf(g_fontes[g_n_fontes].caminho, sizeof g_fontes[0].caminho, "%s", caminho);
    g_n_fontes++;
  }
  closedir(d);
  if (negados)
    nucleo_diagnostico(
        "Sem permissão em %d aparelho(s) de /dev/input. Rode: sudo usermod -aG "
        "input $USER e entre de novo na sessão.",
        negados);
}

static void* laco(void* arg) {
  (void)arg;
  int64_t ultima_varredura = 0;
  for (;;) {
    int64_t agora = plat_agora_us();
    if (agora - ultima_varredura >= REVARRER_MS * 1000) {
      varrer();
      ultima_varredura = agora;
    }
    struct pollfd p[MAX_FDS + 1];
    p[0].fd = g_pipe[0];
    p[0].events = POLLIN;
    for (int i = 0; i < g_n_fontes; i++) {
      p[i + 1].fd = g_fontes[i].fd;
      p[i + 1].events = POLLIN;
    }
    int n = poll(p, g_n_fontes + 1, REVARRER_MS);
    if (n < 0 && errno != EINTR) break;
    if (p[0].revents) break;  // pedido de parada
    for (int i = g_n_fontes - 1; i >= 0; i--) {
      if (p[i + 1].revents & (POLLERR | POLLHUP | POLLNVAL)) {
        fechar_fonte(i);
        continue;
      }
      if (!(p[i + 1].revents & POLLIN)) continue;
      struct input_event ev[64];
      ssize_t r;
      while ((r = read(g_fontes[i].fd, ev, sizeof ev)) > 0) {
        for (size_t k = 0; k < (size_t)r / sizeof *ev; k++) {
          // value: 1 = pressionou, 2 = repetição, 0 = soltou
          if (ev[k].type != EV_KEY || ev[k].value == 0) continue;
          int64_t t = (int64_t)ev[k].input_event_sec * 1000000 + ev[k].input_event_usec;
          nucleo_tecla(g_fontes[i].id, ev[k].code, t);
        }
      }
    }
  }
  for (int i = g_n_fontes - 1; i >= 0; i--) fechar_fonte(i);
  return NULL;
}

int plat_iniciar(void) {
  pthread_condattr_t ca;
  pthread_condattr_init(&ca);
  pthread_condattr_setclock(&ca, CLOCK_MONOTONIC);
  pthread_cond_init(&g_cond, &ca);
  if (pipe2(g_pipe, O_CLOEXEC) != 0) return -1;
  g_n_fontes = 0;
  if (pthread_create(&g_thread, NULL, laco, NULL) != 0) return -2;
  return 0;
}

void plat_parar(void) {
  if (write(g_pipe[1], "x", 1) < 0) { /* ignora */ }
  pthread_join(g_thread, NULL);
  close(g_pipe[0]);
  close(g_pipe[1]);
  g_pipe[0] = g_pipe[1] = -1;
}
