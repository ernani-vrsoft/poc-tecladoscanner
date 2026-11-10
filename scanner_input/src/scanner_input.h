// scanner_input: descobre se cada tecla veio de um TECLADO ou de um SCANNER.
//
// A lib só observa: não bloqueia nem altera nenhuma tecla. O app continua
// recebendo tudo pelo caminho normal e, para cada tecla, pergunta a origem.
//
// Classificação de cada aparelho (automática, sem cadastro):
//   1. fabricante (VID) conhecido de scanner       -> scanner
//   2. nome com "barcode", "scanner", ...           -> scanner
//   3. já aprendido antes (arquivo de estado)       -> scanner
//   4. comportamento: rajada rápida ou regular terminada em Enter -> aprende
//   Senão: teclado.
#ifndef SCANNER_INPUT_H
#define SCANNER_INPUT_H

#include <stdint.h>

#if defined(_WIN32)
#define SI_EXPORT __declspec(dllexport)
#else
#define SI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Tipo de origem.
#define SI_DESCONHECIDO 0  // a lib não viu essa tecla (ex.: teclado virtual)
#define SI_TECLADO 1
#define SI_SCANNER 2

// Motivo da classificação do aparelho.
#define SI_MOTIVO_NENHUM 0       // teclado (nada indicou scanner)
#define SI_MOTIVO_FABRICANTE 1   // VID na tabela
#define SI_MOTIVO_NOME 2         // nome do aparelho
#define SI_MOTIVO_APRENDIDO 3    // gravado no arquivo de estado
#define SI_MOTIVO_VELOCIDADE 4   // rajada rápida terminada em Enter
#define SI_MOTIVO_REGULARIDADE 5 // rajada de ritmo constante terminada em Enter
#define SI_MOTIVO_SEM_APARELHO 6 // tecla injetada (AnyDesk/RDP): sempre teclado
#define SI_MOTIVO_SERIAL 7       // porta serial aguardando a 1ª leitura
#define SI_MOTIVO_PORTA_EM_USO 8 // porta serial aberta por outro programa
#define SI_MOTIVO_SERIAL_TECLADO 9 // porta serial com ritmo de digitação

// Porta serial: rajada rápida (6+ caracteres) = scanner, e fica gravado;
// caracteres soltos com ritmo de gente = teclado serial.

typedef struct {
  int32_t id;          // identificador interno do aparelho
  int32_t tipo;        // SI_TECLADO / SI_SCANNER
  int32_t motivo;      // SI_MOTIVO_*
  int32_t vid;
  int32_t pid;
  int32_t conectado;   // 1 = presente agora
  char nome[128];      // nome informado pelo sistema
  char caminho[256];   // /dev/input/eventX ou \\?\HID#...
} SiAparelho;

// Entrada vinda de porta serial (não passa pelo teclado do sistema).
// Scanner: uma leitura completa (enter = 1).
// Teclado serial: os caracteres conforme chegam; enter = 1 quando veio CR/LF.
typedef struct {
  int32_t aparelho;    // id do aparelho (a porta)
  int32_t tipo;        // SI_SCANNER / SI_TECLADO
  int32_t enter;       // 1 = fim de linha
  char texto[512];     // UTF-8, sem o CR/LF
} SiLeitura;

typedef struct {
  int32_t tipo;        // SI_DESCONHECIDO / SI_TECLADO / SI_SCANNER
  int32_t aparelho;    // id do aparelho, -1 se desconhecido
} SiOrigem;

// Inicia a escuta. arquivo_estado: onde guardar os scanners aprendidos
// (pode ser NULL). Retorna 0 se ok, <0 em erro.
SI_EXPORT int32_t si_iniciar(const char* arquivo_estado);
SI_EXPORT void si_parar(void);

// Origem da tecla física pressionada agora. hid_usage: código USB HID da
// tecla (no Flutter: KeyEvent.physicalKey.usbHidUsage & 0xFFFF).
// Consome o registro correspondente; chame uma vez por KeyDown/KeyRepeat.
SI_EXPORT SiOrigem si_origem_da_tecla(uint32_t hid_usage);

// Copia até `max` aparelhos para `saida`. Retorna quantos copiou.
SI_EXPORT int32_t si_aparelhos(SiAparelho* saida, int32_t max);

// Retira a próxima entrada serial da fila. Retorna 1 se havia, 0 se não.
SI_EXPORT int32_t si_proxima_leitura(SiLeitura* saida);

// Esquece os scanners aprendidos por comportamento.
SI_EXPORT void si_esquecer_aprendidos(void);

// Última mensagem de erro/diagnóstico (ex.: sem permissão em /dev/input).
SI_EXPORT const char* si_diagnostico(void);

#ifdef __cplusplus
}
#endif

#endif
