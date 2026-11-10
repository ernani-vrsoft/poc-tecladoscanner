# Teclado x Scanner

Mostra, para cada tecla, se ela veio de um **TECLADO** ou de um **SCANNER**,
sem cadastro e sem bloquear nada.

- `scanner_input/`: plugin FFI em C. No Linux lê evdev (`/dev/input`); no
  Windows, Raw Input. Também lê as portas seriais.
- `app/`: Flutter. A cada tecla chama `ScannerInput.origemDa(evento)`. As
  entradas seriais chegam por `ScannerInput.leiturasSeriais()`.

A lib **só observa**. Tecla de teclado ou scanner USB chega ao app pelo caminho
normal, e a lib só responde de onde ela veio. Porta serial não gera tecla no
sistema: quem lê a porta é a lib, e ela entrega o texto ao app.

## Ordem de decisão

A decisão é **por aparelho**, não por tecla. Cada aparelho é classificado uma
vez; depois disso, todas as teclas dele herdam a classificação.

### Teclado/scanner USB (e PS/2, Bluetooth)

Ao detectar o aparelho:

| # | Regra                                                                                         | Resultado          |
|---|-----------------------------------------------------------------------------------------------|--------------------|
| 1 | Fabricante (VID) de scanner: Honeywell, Metrologic, Symbol/Zebra, Datalogic, Newland, Opticon | SCANNER            |
| 2 | Nome com `barcode`, `scanner`, `scan`, `leitor`, `hid kbw` ou marca de scanner                | SCANNER            |
| 3 | VID:PID já aprendido antes (arquivo de estado)                                                | SCANNER            |
| 4 | Nenhuma das anteriores                                                                        | TECLADO, observado |

Depois, enquanto o aparelho é usado (só os que ainda são TECLADO):

| # | Regra                                                                                                                | Resultado                |
|---|----------------------------------------------------------------------------------------------------------------------|--------------------------|
| 5 | 6+ caracteres seguidos com média ≤ 35 ms entre teclas (nenhuma > 100 ms) e Enter no fim                              | SCANNER, grava o VID:PID |
| 6 | 8+ caracteres com média ≤ 150 ms e ritmo constante (desvio ≤ 20% da média) e Enter no fim: scanner configurado lento | SCANNER, grava o VID:PID |

Detalhes:

- Shift, Ctrl, Alt e CapsLock não contam para a velocidade.
- Pausa maior que 1 s começa uma rajada nova.
- **Tecla sem aparelho físico** (injetada por AnyDesk, TeamViewer etc. no
  Windows) é sempre TECLADO e nunca aprende.

### Porta serial (Windows: COMx; Linux: ttyUSB*/ttyACM*)

A lib abre a porta a 9600 8N1. A porta começa como "aguardando a primeira
leitura"; se o nome dela já foi aprendido (ex.: `COM3`), entra direto como
SCANNER.

| # | Regra                                                                                           | Resultado                                                      |
|---|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------|
| 1 | Trecho de 6+ caracteres que chega com média ≤ 35 ms (terminado em CR/LF ou em 100 ms sem dados) | SCANNER, grava o nome da porta                                 |
| 2 | Caracteres soltos, no ritmo de quem digita                                                      | TECLADO serial; após 3 toques assim, a porta fica como teclado |

Teclado serial: nos 3 primeiros toques cada tecla demora até 100 ms (a lib
espera a pausa para decidir). Depois disso, cada tecla vai na hora, e CR/LF
vira Enter.

## Cenários

"Genérico" = scanner sem fabricante ou nome conhecido (só a velocidade
identifica). "De marca" = cai na regra 1 ou 2.

### Teclado USB + scanner USB

- **De marca:** SCANNER desde a primeira tecla. Teclado sempre TECLADO.
- **Genérico:** na primeira leitura, os caracteres saem como TECLADO e o Enter
  já como SCANNER (a lib aprendeu). Da segunda em diante, tudo SCANNER, inclusive
  depois de fechar e abrir o app.
- O operador digitando rápido não "contamina" o scanner, e vice-versa, porque
  cada aparelho é medido separado.

### Teclado USB + teclado serial + scanner USB

- Teclado USB: TECLADO.
- Teclado serial: TECLADO (regra serial 2). As teclas chegam pela lib,
  caractere a caractere.
- Scanner USB: como no cenário anterior (de marca: na hora; genérico: aprende
  na primeira leitura).

### Teclado serial + scanner serial

- Cada porta é decidida pela própria primeira entrada: a do scanner chega em
  rajada e vira SCANNER; a do teclado chega tecla a tecla e vira TECLADO.
- A primeira leitura do scanner já sai como SCANNER: na serial, a lib só entrega
  o trecho depois de decidir.
- O aprendido é **pelo nome da porta**. Se trocar os cabos de porta (o teclado
  passa para a COM em que estava o scanner), a porta continua marcada como
  scanner: use "Esquecer aprendidos".

### Teclado USB + teclado serial + scanner USB + scanner serial

Junta os anteriores: cada um dos quatro é classificado sozinho.

- Teclado USB: TECLADO.
- Scanner USB: na hora, se for de marca; aprende na primeira leitura, se for
  genérico.
- Scanner serial: SCANNER pela rajada.
- Teclado serial: TECLADO pelo ritmo.

### Com acesso remoto (AnyDesk, TeamViewer, RDP)

- **Windows, AnyDesk/TeamViewer:** as teclas digitadas remotamente chegam sem
  aparelho físico, então são sempre TECLADO. Um scanner plugado no computador
  **de quem acessa** também chega como TECLADO: para a máquina do PDV ele é só
  texto digitado remotamente.
- **Windows, RDP:** o RDP pode apresentar um teclado virtual com aparelho
  próprio. Ele é tratado como um teclado qualquer. Colar texto remotamente
  ("digitar a área de transferência") em rajada com Enter no fim pode fazê-lo
  aprender como SCANNER.
- **Linux (X11):** teclas remotas são injetadas pelo servidor gráfico e não
  passam pelo `/dev/input`. A lib não as vê, e elas saem como **DESCONHECIDO**,
  cada uma com até 50 ms de espera.
- Os aparelhos físicos da máquina continuam sendo identificados normalmente
  durante o acesso remoto.

### Aparelho plugado com o app aberto

- **USB, Windows:** o Windows avisa na hora, e o aparelho é classificado pelas
  regras 1 a 4.
- **USB, Linux:** o sistema avisa (inotify). A lib espera 300 ms o udev
  terminar e procura de novo; a procura leva ~200 ms. Teclas apertadas nesse
  meio segundo podem sair como DESCONHECIDO.
- **Scanner genérico novo:** a primeira leitura ensina, como no primeiro
  cenário. Se o mesmo modelo (VID:PID) já foi aprendido, é SCANNER na hora.
- **Serial:** no Windows a lib procura portas novas a cada 2 s; no Linux, pelo
  aviso do sistema. A porta nova começa "aguardando a primeira leitura".
- **Desplugou e plugou de novo:** volta com a mesma classificação. Scanner
  aprendido continua aprendido.

### Limites conhecidos

- **Teclado e scanner genérico com o mesmo VID:PID** (mesmo chip barato): depois
  que a lib aprende o scanner, o teclado também passa a ser SCANNER.
- **Scanner genérico configurado muito lento e irregular:** não é reconhecido e
  fica como TECLADO.
- **A primeira leitura de um scanner USB genérico** sai como TECLADO (só o Enter
  sai como SCANNER).

## Rodar

```bash
cd app
flutter run -d linux      # ou -d windows
```

Executáveis prontos: GitHub Actions → build → Artifacts.

Log de depuração (cada tecla vista pela lib e pelo app): rode com a variável
`SI_DEBUG=1`.

## Como testar

1. Abra o app, com a janela em foco.
2. Digite algo no teclado e tecle Enter: aparece como TECLADO.
3. Passe o leitor: aparece como SCANNER. O painel "Aparelhos" mostra cada
   aparelho, como foi classificado e o motivo.
4. "Esquecer aprendidos" apaga o que foi aprendido por comportamento, para
   testar de novo.

Aprendidos ficam em `~/.config/poc_teclado/aprendidos.txt` (Linux) ou
`%APPDATA%\poc_teclado\aprendidos.txt` (Windows).

## Scanner serial (COMx)

A lib precisa abrir a porta. Se outro programa já a abriu (por exemplo, um
programa que "digita" a leitura no Bloco de Notas), o painel mostra a porta
como "aberta por outro programa" e um aviso no topo. Feche esse programa.

Atenção: a POC abre **todas** as portas seriais livres, inclusive de pinpad
ou balança. Feche a POC antes de usar esses equipamentos.

## Linux

Permissão de leitura em `/dev/input`, uma vez por usuário:
`sudo usermod -aG input $USER` (e `dialout` para a serial). Depois, entre de
novo na sessão. Sem isso, o app mostra o aviso no topo.
