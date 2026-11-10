# Teclado x Scanner

Mostra, para cada tecla, se ela veio de um **TECLADO** ou de um **SCANNER**,
sem cadastro e sem bloquear nada.

- `scanner_input/` — plugin FFI em C (Linux: evdev; Windows: Raw Input).
  Escuta todos os aparelhos e classifica cada um sozinho:
  1. fabricante (VID) de scanner conhecido;
  2. nome do aparelho ("barcode", "scanner", ...);
  3. já aprendido antes;
  4. comportamento: rajada rápida (média ≤ 35 ms) ou de ritmo constante
     (scanner lento) terminada em Enter — aprende e grava o VID:PID.
  Teclas injetadas (AnyDesk/RDP, sem aparelho físico) são sempre teclado.
- `app/` — Flutter. A cada tecla chama `ScannerInput.origemDa(evento)`.

## Rodar

```bash
cd app
flutter run -d linux      # ou -d windows
```

Executáveis prontos: GitHub Actions → build → Artifacts.

## Como testar

1. Abra o app (com a janela em foco).
2. Digite algo no teclado + Enter: aparece como TECLADO.
3. Passe o leitor: aparece como SCANNER. O painel "Aparelhos" mostra cada
   aparelho, como foi classificado e o motivo.
4. Scanner genérico (sem marca/nome conhecido): a **primeira** leitura
   ensina a lib. Os caracteres dela aparecem como teclado e o Enter já como
   scanner ("teclas: 0 scanner / N teclado"). Da segunda em diante, tudo
   scanner. "Esquecer aprendidos" apaga isso para testar de novo.

Aprendidos ficam em `~/.config/poc_teclado/aprendidos.txt` (Linux) ou
`%APPDATA%\poc_teclado\aprendidos.txt` (Windows).

## Linux

Permissão de leitura em `/dev/input`, uma vez por usuário:
`sudo usermod -aG input $USER` e entrar de novo na sessão. Sem isso o app
mostra o aviso no topo.
