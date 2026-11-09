# Teclado x Scanner

Mostra cada leitura e de onde ela veio: **SCANNER**, **TECLADO** (aparelho
HID não marcado) ou **SERIAL** (porta COM não marcada). Funciona com scanner
USB HID (que "digita" como teclado) e scanner serial / USB-COM. Só escuta,
nunca bloqueia nada.

- `leitor_dispositivos/` — plugin Flutter genérico (não sabe o que é scanner):
  lista os aparelhos de entrada, mostra quais estão recebendo dados e entrega
  cada leitura com o ID do aparelho de origem.
  - **Serial**: portas COM (`flutter_libserialport`), 9600 8N1, leitura até
    CR/LF ou pausa de 150 ms. Abre só as portas pedidas (`escutarSeriais`) ou
    todas (`escutarTodasSeriais`).
  - **USB HID no Windows**: plugin C++ com hook `WH_GETMESSAGE` na thread de UI
    + Raw Input; manda o texto já com o aparelho de origem por EventChannel.
    `bloquear(ids)` impede que as teclas desses aparelhos cheguem ao resto do app.
  - **USB HID no Linux**: `/dev/input/eventN` casado com o `HardwareKeyboard`.
- `app/` — Flutter. Decide quais aparelhos são scanner (`lib/scanners.dart`,
  salvo em SharedPreferences) e mostra as leituras como SCANNER, TECLADO ou SERIAL.
- `agente/` — Go. Hoje só empacota o app num executável único (ver abaixo);
  a captura não passa mais por ele.

## Gerar o executável único

**Pelo GitHub (recomendado):** a cada push, o GitHub Actions
(`.github/workflows/build.yml`) gera os dois executáveis. Baixe em
Actions → execução → Artifacts. Também dá para rodar manualmente em
Actions → build → Run workflow.

**Na máquina:**

| Sistema | Comando | Resultado |
|---|---|---|
| Windows | `powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1` | `dist\teclado-scanner.exe` |
| Linux | `./scripts/build-linux.sh` | `dist/teclado-scanner` |

O build do Windows precisa ser feito no Windows (Flutter + Visual Studio com
"Desktop development with C++" + Go).

## Rodar em desenvolvimento

```bash
cd app && flutter run -d windows   # ou -d linux
```

## Como testar

1. Abra o app. À esquerda aparecem as portas COM e os aparelhos USB HID.
2. Scanner serial: ligue **Detectar** (abre todas as portas), faça uma leitura
   e veja qual porta acende em verde. Marque **Scanner** nela e desligue
   Detectar (fora disso só as portas marcadas ficam abertas, para não segurar
   balança ou pinpad).
3. Scanner USB HID: com o app em foco, faça uma leitura; o aparelho que
   acender em verde é o scanner. Marque **Scanner** nele.
4. As leituras aparecem à direita como SCANNER, TECLADO ou SERIAL. A escolha
   fica salva.

## Linux

- Scanner USB HID: o usuário precisa estar no grupo `input`
  (`sudo usermod -aG input $USER`, depois sair e entrar na sessão).
- Scanner serial: o usuário precisa estar no grupo `dialout`
  (`sudo usermod -aG dialout $USER`, depois sair e entrar na sessão).
