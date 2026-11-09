import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'fonte.dart';
import 'modelos.dart';

const _pausaFimLeitura = Duration(milliseconds: 150);
const _esperaNovaTentativa = Duration(seconds: 10);
const _timeoutLeitor = 100; // ms

/// Portas seriais. Só abre as portas que [querAberta] pedir, para não segurar
/// a porta de outro equipamento (balança, pinpad) sem necessidade.
class FonteSerial extends Fonte {
  FonteSerial({
    required super.mudou,
    required super.dados,
    required this.leitura,
    required this.querAberta,
    required this.config,
    this.varredura = const Duration(seconds: 2),
  });

  final void Function(String porta, String texto) leitura;
  final bool Function(String porta) querAberta;
  final ConfigSerial config;
  final Duration varredura;

  final _presentes = <String, InfoAparelho>{};
  final _conexoes = <String, _Conexao>{};
  final _abrindo = <String>{};
  final _erros = <String, String>{};
  final _tentarApos = <String, DateTime>{};
  Timer? _timer;
  bool _parado = false;

  @override
  Map<String, InfoAparelho> get presentes => _presentes;
  @override
  Set<String> get escutando => _conexoes.keys.toSet();
  @override
  Map<String, String> get erros => _erros;

  @override
  void iniciar() {
    atualizar();
    _timer = Timer.periodic(varredura, (_) => atualizar());
  }

  @override
  void parar() {
    _parado = true;
    _timer?.cancel();
    for (final c in _conexoes.values.toList()) {
      c.fechar();
    }
    _conexoes.clear();
  }

  /// Revê as portas presentes e abre/fecha conforme [querAberta].
  void atualizar() {
    if (_parado) return;
    var mudouAlgo = false;

    final nomes = SerialPort.availablePorts
        .where((p) => !p.startsWith('/dev/ttyS')) // Linux: portas da placa-mãe, quase sempre vazias
        .toSet();
    for (final nome in nomes) {
      if (!_presentes.containsKey(nome)) {
        _presentes[nome] = _lerInfo(nome);
        mudouAlgo = true;
      }
    }
    for (final nome in _presentes.keys.toList()) {
      if (!nomes.contains(nome)) {
        _presentes.remove(nome);
        _erros.remove(nome);
        _tentarApos.remove(nome);
        mudouAlgo = true;
      }
    }

    for (final nome in _conexoes.keys.toList()) {
      if (!nomes.contains(nome) || !querAberta(nome)) {
        _conexoes.remove(nome)!.fechar();
        mudouAlgo = true;
      }
    }
    for (final nome in _erros.keys.toList()) {
      if (!querAberta(nome)) {
        _erros.remove(nome);
        _tentarApos.remove(nome);
        mudouAlgo = true;
      }
    }

    final agora = DateTime.now();
    for (final nome in nomes) {
      if (querAberta(nome) &&
          !_conexoes.containsKey(nome) &&
          !_abrindo.contains(nome) &&
          !(_tentarApos[nome]?.isAfter(agora) ?? false)) {
        _abrir(nome);
      }
    }

    if (mudouAlgo) mudou();
  }

  InfoAparelho _lerInfo(String nome) {
    final p = SerialPort(nome);
    try {
      final vid = p.vendorId;
      final pid = p.productId;
      final produto = p.productName ?? '';
      final fabricante = p.manufacturer ?? '';
      final vidPid = vid == null || pid == null ? '' : '${_hex(vid)}:${_hex(pid)}';
      final transporte = switch (p.transport) {
        SerialPortTransport.usb => 'USB',
        SerialPortTransport.bluetooth => 'Bluetooth',
        _ => 'Nativa',
      };
      final descricao = [
        p.description ?? '',
        if (fabricante.isNotEmpty) fabricante,
        transporte,
      ].where((s) => s.isNotEmpty).join(' · ');
      return InfoAparelho(
        nome,
        produto.isEmpty ? nome : '$nome · $produto',
        descricao,
        vidPid,
      );
    } catch (_) {
      return InfoAparelho(nome, nome, '', '');
    } finally {
      p.dispose();
    }
  }

  Future<void> _abrir(String nome) async {
    _abrindo.add(nome);
    final porta = SerialPort(nome);
    final endereco = porta.address;
    String? erro;
    try {
      // Numa isolate à parte: no Windows, abrir uma COM de Bluetooth pode
      // travar vários segundos e congelaria a tela.
      erro = await _abrirEmIsolate(endereco, config);
    } catch (e) {
      erro = '$e';
    }
    _abrindo.remove(nome);

    if (erro != null || _parado || !querAberta(nome)) {
      if (erro == null) porta.close();
      porta.dispose();
      if (erro != null && !_parado && querAberta(nome)) {
        _erros[nome] = erro;
        _tentarApos[nome] = DateTime.now().add(_esperaNovaTentativa);
        mudou();
      }
      return;
    }

    _erros.remove(nome);
    _tentarApos.remove(nome);
    _conexoes[nome] = _Conexao(
      porta,
      aoReceber: (bytes) => dados(nome),
      aoLer: (texto) => leitura(nome, texto),
      aoCair: () {
        _conexoes.remove(nome)?.fechar();
        mudou();
      },
    );
    mudou();
  }

  static String _hex(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
}

// Fora da classe de propósito: um closure criado dentro de um método leva
// junto o contexto do método (inclusive `this`, com Timers), e o Isolate.run
// recusa enviar isso para a outra isolate.
Future<String?> _abrirEmIsolate(int endereco, ConfigSerial c) {
  final baud = c.baudRate, bits = c.bits, paridade = c.paridade, stop = c.stopBits;
  return Isolate.run(() => _abrirNativo(endereco, baud, bits, paridade, stop));
}

String? _abrirNativo(int endereco, int baud, int bits, int paridade, int stop) {
  final p = SerialPort.fromAddress(endereco);
  if (!p.openRead()) {
    return SerialPort.lastError?.message ?? 'Não foi possível abrir';
  }
  try {
    final cfg = SerialPortConfig()
      ..baudRate = baud
      ..bits = bits
      ..parity = paridade
      ..stopBits = stop;
    cfg.setFlowControl(SerialPortFlowControl.none);
    // Leitores USB-COM (CDC) costumam só enviar com DTR ligado.
    cfg
      ..dtr = SerialPortDtr.on
      ..rts = SerialPortRts.on;
    p.config = cfg;
    p.flush(SerialPortBuffer.input); // descarta o que chegou antes de abrir
    return null;
  } catch (e) {
    p.close();
    return '$e';
  }
}

/// Uma porta aberta: junta os bytes até CR/LF ou uma pausa curta (aparelho
/// configurado sem sufixo).
class _Conexao {
  _Conexao(
    this.porta, {
    required this.aoReceber,
    required this.aoLer,
    required this.aoCair,
  }) {
    _leitor = SerialPortReader(porta, timeout: _timeoutLeitor);
    _sub = _leitor.stream.listen(
      _receber,
      onError: (_) => aoCair(),
      onDone: aoCair,
    );
  }

  final SerialPort porta;
  final void Function(Uint8List bytes) aoReceber;
  final void Function(String texto) aoLer;
  final void Function() aoCair;

  late final SerialPortReader _leitor;
  late final StreamSubscription<Uint8List> _sub;
  final _texto = BytesBuilder();
  Timer? _pausa;
  bool _fechada = false;

  void _receber(Uint8List bytes) {
    aoReceber(bytes);
    for (final b in bytes) {
      if (b == 0x0D || b == 0x0A) {
        _enviar();
      } else {
        _texto.addByte(b);
      }
    }
    _pausa?.cancel();
    if (_texto.isNotEmpty) _pausa = Timer(_pausaFimLeitura, _enviar);
  }

  void _enviar() {
    final t = utf8.decode(_texto.takeBytes(), allowMalformed: true).trim();
    if (t.isNotEmpty && !_fechada) aoLer(t);
  }

  void fechar() {
    if (_fechada) return;
    _fechada = true;
    _pausa?.cancel();
    _sub.cancel();
    _leitor.close();
    // A isolate do leitor pode estar dentro de uma espera nativa: só libera a
    // porta depois que essa espera termina.
    Timer(const Duration(milliseconds: _timeoutLeitor * 3), () {
      porta.close();
      porta.dispose();
    });
  }
}
