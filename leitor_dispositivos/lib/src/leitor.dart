import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'fonte.dart';
import 'hid_linux.dart';
import 'hid_windows.dart';
import 'modelos.dart';
import 'serial.dart';

/// Leitor genérico de aparelhos de entrada: portas seriais e aparelhos USB
/// HID que digitam como teclado. Lista os aparelhos, mostra quais estão
/// recebendo dados e entrega cada leitura com o ID do aparelho de origem.
/// O que fazer com cada aparelho (ex: tratar como leitor de código de barras)
/// fica com o app.
///
/// Serial: o texto vem da porta. HID no Windows: o plugin nativo manda o
/// texto já com o aparelho de origem. HID no Linux: o caractere vem do
/// Flutter e a origem de /dev/input; as duas chegam na mesma ordem e são
/// casadas uma a uma. Nos dois casos as leituras HID só são montadas com o app
/// em foco (sem foco, a tecla vai para outro programa).
class LeitorDispositivos extends ChangeNotifier {
  LeitorDispositivos({
    this.config = const ConfigSerial(),
    this.janelaAtividade = const Duration(seconds: 1),
  });

  final ConfigSerial config;

  /// Por quanto tempo um aparelho aparece como "recebendo" após o último dado.
  final Duration janelaAtividade;

  Set<String> _portasSeriais = {};
  bool _escutarTodasSeriais = false;
  Set<String> _bloqueados = {};
  final _ultimoDado = <String, DateTime>{};
  final _leituras = StreamController<Leitura>.broadcast();

  FonteSerial? _serial;
  Fonte? _hid;
  Timer? _relogio;
  Set<String> _recebendoAntes = {};

  final _origens = <(String, DateTime)>[];
  final _teclas = <(KeyDownEvent, DateTime)>[];
  final _digitando = <String, String>{};

  /// Leituras completas de todos os aparelhos escutados.
  Stream<Leitura> get leituras => _leituras.stream;

  /// Texto HID sendo digitado agora, por aparelho (até o Enter).
  Map<String, String> get digitando => Map.unmodifiable(_digitando);

  /// Portas seriais que ficam abertas. As outras ficam fechadas para não
  /// segurar a porta de outro equipamento (balança, pinpad).
  Set<String> get portasSeriais => Set.unmodifiable(_portasSeriais);
  void escutarSeriais(Iterable<String> portas) {
    _portasSeriais = portas.toSet();
    _serial?.atualizar();
    notifyListeners();
  }

  /// Abre todas as portas seriais, ex: para descobrir qual recebe dados.
  bool get escutarTodasSeriais => _escutarTodasSeriais;
  set escutarTodasSeriais(bool v) {
    if (_escutarTodasSeriais == v) return;
    _escutarTodasSeriais = v;
    _serial?.atualizar();
    notifyListeners();
  }

  /// Aparelhos HID cujas teclas não chegam ao resto do app (campo em foco,
  /// atalhos): só viram leitura. Só no Windows; outros programas não são
  /// afetados.
  Set<String> get bloqueados => Set.unmodifiable(_bloqueados);
  void bloquear(Iterable<String> ids) {
    _bloqueados = ids.toSet();
    _enviarBloqueio();
    notifyListeners();
  }

  void _enviarBloqueio() {
    final hid = _hid;
    if (hid is FonteHidWindows) hid.bloquear(_bloqueados);
  }

  List<Dispositivo> get dispositivos {
    final agora = DateTime.now();
    Iterable<Dispositivo> de(Fonte? f, TipoDispositivo tipo) {
      if (f == null) return const [];
      final escutando = f.escutando;
      final nomes = f.presentes.keys.toList()..sort(compararNomes);
      return nomes.map((id) {
        final info = f.presentes[id]!;
        final ultimo = _ultimoDado[id];
        return Dispositivo(
          id: id,
          tipo: tipo,
          nome: info.nome,
          descricao: info.descricao,
          vidPid: info.vidPid,
          escutando: escutando.contains(id),
          bloqueado: tipo == TipoDispositivo.hid && _bloqueados.contains(id),
          recebendo: ultimo != null && agora.difference(ultimo) < janelaAtividade,
          ultimoDado: ultimo,
          erro: f.erros[id],
        );
      });
    }

    return [...de(_serial, TipoDispositivo.serial), ...de(_hid, TipoDispositivo.hid)];
  }

  /// Erro geral da captura HID (ex: Raw Input indisponível).
  String? get erroHid => _hid?.erros['*'];

  void iniciar() {
    _serial = FonteSerial(
      mudou: notifyListeners,
      dados: _marcarDado,
      leitura: _leituraSerial,
      querAberta: (p) => _escutarTodasSeriais || _portasSeriais.contains(p),
      config: config,
    )..iniciar();

    if (Platform.isWindows) {
      _hid = FonteHidWindows(
        mudou: notifyListeners,
        dados: _marcarDado,
        texto: _digitar,
        apagar: _apagar,
        enter: _enter,
      );
    } else if (Platform.isLinux) {
      _hid = FonteHidLinux(mudou: notifyListeners, dados: _marcarDado, tecla: _origem);
      HardwareKeyboard.instance.addHandler(_teclaApp);
    }
    _hid?.iniciar();
    _enviarBloqueio();

    _relogio = Timer.periodic(const Duration(milliseconds: 250), (_) => _verAtividade());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_teclaApp);
    _relogio?.cancel();
    _serial?.parar();
    _hid?.parar();
    _leituras.close();
    super.dispose();
  }

  void _marcarDado(String id) {
    _ultimoDado[id] = DateTime.now();
    if (!_recebendoAntes.contains(id)) _verAtividade();
  }

  /// Avisa só quando algum aparelho começa ou para de receber.
  void _verAtividade() {
    final agora = DateTime.now();
    final recebendo = {
      for (final e in _ultimoDado.entries)
        if (agora.difference(e.value) < janelaAtividade) e.key,
    };
    if (!setEquals(recebendo, _recebendoAntes)) {
      _recebendoAntes = recebendo;
      notifyListeners();
    }
  }

  void _leituraSerial(String porta, String texto) {
    _leituras.add(Leitura(
      dispositivoId: porta,
      tipo: TipoDispositivo.serial,
      nome: _serial?.presentes[porta]?.nome ?? porta,
      texto: texto,
    ));
  }

  void _origem(String id) {
    _origens.add((id, DateTime.now()));
    _parear();
  }

  bool _teclaApp(KeyEvent e) {
    if (e is KeyDownEvent && !e.synthesized) {
      _teclas.add((e, DateTime.now()));
      _parear();
    }
    return false; // não consome a tecla
  }

  /// Casa a 1ª origem com a 1ª tecla do app, e assim por diante. Sobras com
  /// mais de 1 segundo (tecla com o app sem foco) são descartadas.
  void _parear() {
    final limite = DateTime.now().subtract(const Duration(seconds: 1));
    _origens.removeWhere((o) => o.$2.isBefore(limite));
    _teclas.removeWhere((t) => t.$2.isBefore(limite));
    while (_origens.isNotEmpty && _teclas.isNotEmpty) {
      _aplicar(_origens.removeAt(0).$1, _teclas.removeAt(0).$1);
    }
  }

  void _aplicar(String id, KeyDownEvent e) {
    final tecla = e.logicalKey;
    if (tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) {
      _enter(id);
    } else if (tecla == LogicalKeyboardKey.backspace) {
      _apagar(id);
    } else {
      final c = e.character;
      if (c != null && c.isNotEmpty && c.codeUnitAt(0) >= 0x20) _digitar(id, c);
    }
  }

  void _digitar(String id, String texto) {
    if (texto.isEmpty) return;
    _digitando[id] = (_digitando[id] ?? '') + texto;
    notifyListeners();
  }

  void _apagar(String id) {
    final texto = _digitando[id];
    if (texto == null || texto.isEmpty) return;
    _digitando[id] = texto.characters.skipLast(1).toString();
    notifyListeners();
  }

  void _enter(String id) {
    final texto = _digitando.remove(id) ?? '';
    if (texto.isNotEmpty) {
      _leituras.add(Leitura(
        dispositivoId: id,
        tipo: TipoDispositivo.hid,
        nome: _hid?.presentes[id]?.nome ?? id,
        texto: texto,
      ));
    }
    notifyListeners();
  }
}
