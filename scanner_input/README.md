# scanner_input

Plugin FFI (C) que diz, para cada tecla, se ela veio de um **teclado** ou de
um **scanner**. Só observa: não bloqueia nem altera teclas.

```dart
ScannerInput.iniciar();
final origem = ScannerInput.origemDa(keyEvent); // chame em KeyDown/KeyRepeat
if (origem.ehScanner) { ... }
```

Código nativo em `src/` (núcleo comum + `si_linux.c` / `si_windows.c`).
