import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'fonte.dart';

const _evKey = 1;
const _tamEvento = 24; // struct input_event em 64 bits
const _keyEnter = 28;
const _esperaNovaTentativa = Duration(seconds: 10);

/// Teclados e outros aparelhos USB HID no Linux, lendo /dev/input/eventN. Cada
/// arquivo é um aparelho. Leitura sem "grab": nada é bloqueado.
/// Precisa que o usuário esteja no grupo "input".
class FonteHidLinux extends Fonte {
  FonteHidLinux({
    required super.mudou,
    required super.dados,
    required this.tecla,
    this.varredura = const Duration(seconds: 2),
  });

  final void Function(String id) tecla;
  final Duration varredura;

  final _presentes = <String, InfoAparelho>{};
  final _abertos = <String, StreamSubscription<List<int>>>{}; // por eventN
  final _idPorEvento = <String, String>{};
  final _erros = <String, String>{};
  final _tentarApos = <String, DateTime>{};
  Timer? _timer;

  @override
  Map<String, InfoAparelho> get presentes => _presentes;
  @override
  Set<String> get escutando =>
      {for (final e in _abertos.keys) ?_idPorEvento[e]};
  @override
  Map<String, String> get erros => _erros;

  @override
  void iniciar() {
    _varrer();
    _timer = Timer.periodic(varredura, (_) => _varrer());
  }

  @override
  void parar() {
    _timer?.cancel();
    for (final s in _abertos.values) {
      s.cancel();
    }
    _abertos.clear();
  }

  void _varrer() {
    var mudouAlgo = false;
    final vistos = <String>{};
    final agora = DateTime.now();

    final dir = Directory('/sys/class/input');
    final eventos = dir.existsSync()
        ? dir.listSync().map((e) => e.path).where((p) => p.split('/').last.startsWith('event'))
        : const <String>[];

    for (final sys in eventos) {
      if (!_ehTeclado(sys)) continue;
      final evento = sys.split('/').last;
      final info = _info(sys, evento);
      vistos.add(evento);
      _idPorEvento[evento] = info.id;
      if (!_presentes.containsKey(info.id)) {
        _presentes[info.id] = info;
        mudouAlgo = true;
      }
      if (_abertos.containsKey(evento) || (_tentarApos[info.id]?.isAfter(agora) ?? false)) {
        continue;
      }
      _abrir(evento, info.id);
    }

    for (final evento in _idPorEvento.keys.toList()) {
      if (!vistos.contains(evento)) {
        final id = _idPorEvento.remove(evento)!;
        _abertos.remove(evento)?.cancel();
        _presentes.remove(id);
        _erros.remove(id);
        mudouAlgo = true;
      }
    }
    if (mudouAlgo) mudou();
  }

  void _abrir(String evento, String id) {
    final sobra = BytesBuilder();
    final sub = File('/dev/input/$evento').openRead().listen(
      (bloco) {
        sobra.add(bloco);
        final bytes = sobra.takeBytes();
        final dadosEv = ByteData.sublistView(bytes);
        var i = 0;
        for (; i + _tamEvento <= bytes.length; i += _tamEvento) {
          final tipo = dadosEv.getUint16(i + 16, Endian.little);
          final valor = dadosEv.getInt32(i + 20, Endian.little); // 0 solta, 1 aperta, 2 repete
          if (tipo == _evKey && valor == 1) {
            dados(id);
            tecla(id);
          }
        }
        if (i < bytes.length) sobra.add(bytes.sublist(i));
      },
      onError: (Object e) {
        _abertos.remove(evento)?.cancel();
        if (e is FileSystemException && e.osError?.errorCode == 13) {
          _erros[id] =
              'Sem permissão. Rode: sudo usermod -aG input \$USER e entre de novo na sessão.';
        } else {
          _erros[id] = '$e';
        }
        _tentarApos[id] = DateTime.now().add(_esperaNovaTentativa);
        mudou();
      },
      onDone: () {
        _abertos.remove(evento);
        mudou();
      },
      cancelOnError: true,
    );
    _abertos[evento] = sub;
    _erros.remove(id);
    mudou();
  }

  static String _ler(String sys, String arq) {
    try {
      return File('$sys/$arq').readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  /// Aparelho que tem as teclas "1" e Enter.
  static bool _ehTeclado(String sys) {
    final palavras = _ler(sys, 'device/capabilities/key').split(RegExp(r'\s+'));
    if (palavras.isEmpty || palavras.last.isEmpty) return false;
    final baixo = BigInt.tryParse(palavras.last, radix: 16);
    if (baixo == null) return false;
    bool tem(int bit) => (baixo >> bit) & BigInt.one == BigInt.one;
    return tem(2) && tem(_keyEnter);
  }

  static InfoAparelho _info(String sys, String evento) {
    // A porta física (phys) identifica o aparelho: dois aparelhos iguais em
    // portas USB diferentes ficam com IDs diferentes.
    final phys = _ler(sys, 'device/phys');
    final nome = _ler(sys, 'device/name');
    final vid = _ler(sys, 'device/id/vendor').toUpperCase();
    final pid = _ler(sys, 'device/id/product').toUpperCase();
    return InfoAparelho(
      phys.isEmpty ? evento : phys,
      nome.isEmpty ? 'Teclado' : nome,
      '/dev/input/$evento${phys.isEmpty ? '' : ' · $phys'}',
      vid.isEmpty || pid.isEmpty ? '' : '$vid:$pid',
    );
  }
}
