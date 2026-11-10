// Contrato interno entre o núcleo (si_nucleo.c) e a parte de cada sistema
// (si_linux.c / si_windows.c). Nada aqui é exportado.
#ifndef SI_INTERNO_H
#define SI_INTERNO_H

#include <stdint.h>

#include "scanner_input.h"

// ---- Fornecido pela parte do sistema ----
int plat_iniciar(void);     // abre os aparelhos e cria a thread de escuta
void plat_parar(void);
void plat_travar(void);     // mutex do estado compartilhado
void plat_destravar(void);
void plat_aguardar(int ms); // espera um sinal (com a trava tomada) ou o tempo
void plat_sinalizar(void);  // acorda quem está em plat_aguardar
int64_t plat_agora_us(void);

// ---- Fornecido pelo núcleo (chamar SEM a trava tomada) ----
// Registra (ou reconecta) um aparelho. `chave` é única por aparelho físico
// enquanto conectado (caminho do sistema). Retorna o id.
int nucleo_aparelho_conectado(const char* chave, const char* nome, int vid,
                              int pid, int sem_aparelho);
void nucleo_aparelho_desconectado(const char* chave);
// Tecla pressionada (ou repetida). `codigo` é o código evdev da tecla
// (no Windows, o scancode é convertido antes). t_us: momento da tecla.
void nucleo_tecla(int aparelho, int codigo, int64_t t_us);
void nucleo_diagnostico(const char* fmt, ...);
// Porta serial: aberta (scanner) ou ocupada por outro programa.
int nucleo_porta(const char* nome, int em_uso);
// Bytes lidos da porta; o núcleo junta até CR/LF ou até `fim_por_pausa`.
void nucleo_bytes_serial(int aparelho, const char* bytes, int n);
void nucleo_pausa_serial(int aparelho);  // nada chegou por um tempo

// Converte scancode set 1 (Windows, com flag E0) para código evdev.
int si_scancode_para_evdev(int scancode, int e0);

#endif
