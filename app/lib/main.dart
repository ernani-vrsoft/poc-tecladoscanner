import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scanner_input/scanner_input.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final r = ScannerInput.iniciar(arquivoEstado: _arquivoEstado());
  runApp(App(erroInicio: r == 0 ? null : 'si_iniciar retornou $r'));
}

String? _arquivoEstado() {
  final base = Platform.isWindows
      ? Platform.environment['APPDATA']
      : '${Platform.environment['HOME']}/.config';
  if (base == null) return null;
  final dir = Directory('$base${Platform.pathSeparator}poc_teclado')..createSync(recursive: true);
  return '${dir.path}${Platform.pathSeparator}aprendidos.txt';
}

class App extends StatelessWidget {
  const App({super.key, this.erroInicio});
  final String? erroInicio;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Teclado x Scanner',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: Tela(erroInicio: erroInicio),
  );
}

class Leitura {
  Leitura(
    this.texto,
    this.origem,
    this.teclasScanner,
    this.teclasTeclado,
    this.hora, {
    this.serial = false,
  });
  final String texto;
  final OrigemTecla origem; // origem do Enter, que fecha a leitura
  final int teclasScanner;
  final int teclasTeclado;
  final DateTime hora;
  final bool serial;
}

class Tela extends StatefulWidget {
  const Tela({super.key, this.erroInicio});
  final String? erroInicio;

  @override
  State<Tela> createState() => _TelaState();
}

class _TelaState extends State<Tela> {
  final _leituras = <Leitura>[];
  final _buffer = StringBuffer();
  int _scanner = 0, _teclado = 0;
  OrigemTecla? _ultima;
  List<Aparelho> _aparelhos = [];
  late final Timer _timer;
  late final Timer _timerSerial;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tecla);
    _atualizarAparelhos();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _atualizarAparelhos());
    _timerSerial = Timer.periodic(const Duration(milliseconds: 50), (_) => _lerSerial());
  }

  // Scanner serial não gera tecla: a leitura chega pronta da lib.
  void _lerSerial() {
    final novas = ScannerInput.leiturasSeriais();
    if (novas.isEmpty) return;
    setState(() {
      for (final l in novas) {
        _leituras.insert(
          0,
          Leitura(
            l.texto,
            OrigemTecla(TipoOrigem.scanner, l.aparelho),
            0,
            0,
            DateTime.now(),
            serial: true,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tecla);
    _timer.cancel();
    _timerSerial.cancel();
    super.dispose();
  }

  void _atualizarAparelhos() => setState(() => _aparelhos = ScannerInput.aparelhos());

  // Só observa: devolve false para a tecla seguir o caminho normal do app.
  bool _tecla(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final origem = ScannerInput.origemDa(e);
    setState(() {
      _ultima = origem;
      final enter =
          e.logicalKey == LogicalKeyboardKey.enter ||
          e.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (enter) {
        if (_buffer.isNotEmpty) {
          _leituras.insert(
            0,
            Leitura(_buffer.toString(), origem, _scanner, _teclado, DateTime.now()),
          );
        }
        _buffer.clear();
        _scanner = _teclado = 0;
      } else if (e.character != null &&
          e.character!.isNotEmpty &&
          e.character!.codeUnitAt(0) >= 32) {
        _buffer.write(e.character);
        origem.ehScanner ? _scanner++ : _teclado++;
      } else if (e.logicalKey == LogicalKeyboardKey.backspace && _buffer.isNotEmpty) {
        final s = _buffer.toString();
        _buffer
          ..clear()
          ..write(s.substring(0, s.length - 1));
      }
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final diag = widget.erroInicio ?? ScannerInput.diagnostico();
    return Scaffold(
      appBar: AppBar(title: const Text('Teclado x Scanner')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (diag.isNotEmpty)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(diag)),
              ),
            _Digitando(texto: _buffer.toString(), ultima: _ultima),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _ListaLeituras(_leituras)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _ListaAparelhos(
                      _aparelhos,
                      onEsquecer: () {
                        ScannerInput.esquecerAprendidos();
                        _atualizarAparelhos();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _cor(TipoOrigem t) => switch (t) {
  TipoOrigem.scanner => Colors.green.shade700,
  TipoOrigem.teclado => Colors.blue.shade700,
  TipoOrigem.desconhecido => Colors.grey,
};

String _rotulo(TipoOrigem t) => switch (t) {
  TipoOrigem.scanner => 'SCANNER',
  TipoOrigem.teclado => 'TECLADO',
  TipoOrigem.desconhecido => 'DESCONHECIDO',
};

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.tipo);
  final TipoOrigem tipo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: _cor(tipo), borderRadius: BorderRadius.circular(4)),
    child: Text(
      _rotulo(tipo),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
    ),
  );
}

class _Digitando extends StatelessWidget {
  const _Digitando({required this.texto, required this.ultima});
  final String texto;
  final OrigemTecla? ultima;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Text('Digitando: '),
          Expanded(
            child: Text(
              texto.isEmpty ? '(digite no teclado ou passe o leitor; Enter fecha)' : texto,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
          ),
          if (ultima != null) ...[
            const Text('última tecla: '),
            _Etiqueta(ultima!.tipo),
            const SizedBox(width: 8),
            Text(ultima!.aparelho?.nome ?? ''),
          ],
        ],
      ),
    ),
  );
}

class _ListaLeituras extends StatelessWidget {
  const _ListaLeituras(this.leituras);
  final List<Leitura> leituras;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Leituras (fechadas com Enter)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: leituras.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = leituras[i];
              final h = l.hora;
              final hora =
                  '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}:${h.second.toString().padLeft(2, '0')}';
              return ListTile(
                dense: true,
                leading: _Etiqueta(l.origem.tipo),
                title: SelectableText(l.texto, style: const TextStyle(fontFamily: 'monospace')),
                subtitle: Text(
                  '$hora · ${l.origem.aparelho?.nome ?? 'aparelho desconhecido'}'
                  ' · ${l.serial ? 'leitura serial' : 'teclas: ${l.teclasScanner} scanner / ${l.teclasTeclado} teclado'}',
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ListaAparelhos extends StatelessWidget {
  const _ListaAparelhos(this.aparelhos, {required this.onEsquecer});
  final List<Aparelho> aparelhos;
  final VoidCallback onEsquecer;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('Aparelhos', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(onPressed: onEsquecer, child: const Text('Esquecer aprendidos')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              for (final a in aparelhos)
                Opacity(
                  opacity: a.conectado ? 1 : 0.4,
                  child: ListTile(
                    dense: true,
                    leading: _Etiqueta(a.tipo),
                    title: Text(a.nome.isEmpty ? '(sem nome)' : a.nome),
                    subtitle: Text(
                      '${a.vidPid} · ${a.motivo.descricao}'
                      '${a.conectado ? '' : ' · desconectado'}\n${a.caminho}',
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
