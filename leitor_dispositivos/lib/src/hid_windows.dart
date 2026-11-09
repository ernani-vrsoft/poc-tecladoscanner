import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'fonte.dart';

/// Teclados e outros aparelhos USB HID no Windows. A captura é do plugin nativo
/// (windows/leitor_dispositivos_plugin.cpp), que já manda o texto com o aparelho
/// de origem; aqui só se lista os aparelhos e se repassa os eventos.
class FonteHidWindows extends Fonte {
  FonteHidWindows({
    required super.mudou,
    required super.dados,
    required this.texto,
    required this.apagar,
    required this.enter,
    this.varredura = const Duration(seconds: 2),
  });

  final void Function(String id, String texto) texto;
  final void Function(String id) apagar;
  final void Function(String id) enter;
  final Duration varredura;

  static const idSoftware = 'SEM-APARELHO';
  static const _eventos = EventChannel('leitor_dispositivos/teclado');
  static const _comandos = MethodChannel('leitor_dispositivos');

  final _presentes = <String, InfoAparelho>{};
  final _porHandle = <int, String>{};
  final _erros = <String, String>{};
  StreamSubscription<dynamic>? _sub;
  Timer? _timer;

  @override
  Map<String, InfoAparelho> get presentes => _presentes;
  @override
  Set<String> get escutando => _presentes.keys.toSet();
  @override
  Map<String, String> get erros => _erros;

  @override
  void iniciar() {
    _listar();
    _timer = Timer.periodic(varredura, (_) => _listar());
    _sub = _eventos.receiveBroadcastStream().listen(_evento);
  }

  @override
  void parar() {
    _timer?.cancel();
    _sub?.cancel();
  }

  /// Teclas destes aparelhos não chegam ao Flutter (só à lib).
  Future<void> bloquear(Iterable<String> ids) =>
      _comandos.invokeMethod('bloquear', ids.toList());

  void _evento(dynamic e) {
    if (e is! Map) return;
    final id = e['id'] as String? ?? '';
    switch (e['tipo']) {
      case 'atividade':
        _garantir(id);
        dados(id);
      case 'texto':
        texto(id, e['texto'] as String? ?? '');
      case 'apagar':
        apagar(id);
      case 'enter':
        enter(id);
      case 'erro':
        _erros['*'] = e['texto'] as String? ?? 'Erro na captura';
        mudou();
    }
  }

  /// Aparelho que mandou tecla antes da próxima varredura (ou que não aparece
  /// na lista, como a entrada por software).
  void _garantir(String id) {
    if (_presentes.containsKey(id)) return;
    _presentes[id] = id == idSoftware
        ? const InfoAparelho(
            idSoftware,
            'Entrada por software',
            'Teclado virtual, área de trabalho remota...',
            '',
          )
        : InfoAparelho(id, 'Teclado', id, '');
    mudou();
  }

  void _listar() {
    final atuais = <int, InfoAparelho>{
      for (final h in _w.tecladosConectados())
        h: _presentes[_porHandle[h]] ?? _info(h),
    };
    var mudouAlgo = false;
    final ids = atuais.values.map((i) => i.id).toSet();
    for (final e in atuais.entries) {
      _porHandle[e.key] = e.value.id;
      final antes = _presentes[e.value.id];
      if (antes == null || antes.nome != e.value.nome) {
        _presentes[e.value.id] = e.value;
        mudouAlgo = true;
      }
    }
    for (final id in _presentes.keys.toList()) {
      if (id != idSoftware && !ids.contains(id)) {
        _presentes.remove(id);
        _porHandle.removeWhere((_, v) => v == id);
        mudouAlgo = true;
      }
    }
    if (mudouAlgo) mudou();
  }

  InfoAparelho _info(int handle) {
    final caminho = _w.caminhoAparelho(handle);
    if (caminho.isEmpty) return const InfoAparelho('DESCONHECIDO', 'Teclado', '', '');
    final produto = _w.nomeProduto(caminho);
    final m = RegExp(r'VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})', caseSensitive: false)
        .firstMatch(caminho);
    final vidPid = m == null ? '' : '${m[1]!.toUpperCase()}:${m[2]!.toUpperCase()}';
    final virtual = !caminho.toUpperCase().contains('HID#');
    return InfoAparelho(
      caminho.toUpperCase(),
      produto.isNotEmpty
          ? produto
          : (virtual ? 'Teclado virtual / sistema' : 'Teclado HID'),
      caminho,
      vidPid,
    );
  }
}

const _ridiDeviceName = 0x20000007;
const _rimTypeKeyboard = 1;

final class _RawInputDeviceList extends Struct {
  @IntPtr()
  external int hDevice;
  @Uint32()
  external int dwType;
}

class _Win32 {
  final _user32 = DynamicLibrary.open('user32.dll');
  final _kernel32 = DynamicLibrary.open('kernel32.dll');
  final _hid = DynamicLibrary.open('hid.dll');

  late final getRawInputDeviceList = _user32.lookupFunction<
    Uint32 Function(Pointer<_RawInputDeviceList>, Pointer<Uint32>, Uint32),
    int Function(Pointer<_RawInputDeviceList>, Pointer<Uint32>, int)
  >('GetRawInputDeviceList');
  late final getRawInputDeviceInfo = _user32.lookupFunction<
    Uint32 Function(IntPtr, Uint32, Pointer<Void>, Pointer<Uint32>),
    int Function(int, int, Pointer<Void>, Pointer<Uint32>)
  >('GetRawInputDeviceInfoW');
  late final createFile = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr),
    int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
  >('CreateFileW');
  late final closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  late final hidGetProductString = _hid.lookupFunction<
    Uint8 Function(IntPtr, Pointer<Void>, Uint32),
    int Function(int, Pointer<Void>, int)
  >('HidD_GetProductString');

  List<int> tecladosConectados() {
    final n = calloc<Uint32>();
    try {
      final tam = sizeOf<_RawInputDeviceList>();
      if (getRawInputDeviceList(nullptr, n, tam) == 0xFFFFFFFF || n.value == 0) {
        return const [];
      }
      final lista = calloc<_RawInputDeviceList>(n.value);
      try {
        final total = getRawInputDeviceList(lista, n, tam);
        if (total == 0xFFFFFFFF) return const [];
        return [
          for (var i = 0; i < total; i++)
            if (lista[i].dwType == _rimTypeKeyboard) lista[i].hDevice,
        ];
      } finally {
        calloc.free(lista);
      }
    } finally {
      calloc.free(n);
    }
  }

  String caminhoAparelho(int handle) {
    final tam = calloc<Uint32>();
    try {
      getRawInputDeviceInfo(handle, _ridiDeviceName, nullptr, tam);
      if (tam.value == 0) return '';
      final buf = calloc<Uint16>(tam.value + 1);
      try {
        final r = getRawInputDeviceInfo(handle, _ridiDeviceName, buf.cast(), tam);
        if (r == 0xFFFFFFFF || r == 0) return '';
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(tam);
    }
  }

  String nomeProduto(String caminho) {
    final p = caminho.toNativeUtf16();
    try {
      // Acesso 0: só consulta informações, não abre o teclado para leitura.
      const shareReadWrite = 0x1 | 0x2, openExisting = 3, invalido = -1;
      final f = createFile(p, 0, shareReadWrite, nullptr, openExisting, 0, 0);
      if (f == invalido || f == 0) return '';
      final buf = calloc<Uint16>(127);
      try {
        if (hidGetProductString(f, buf.cast(), 127 * 2) == 0) return '';
        return buf.cast<Utf16>().toDartString().trim();
      } finally {
        calloc.free(buf);
        closeHandle(f);
      }
    } finally {
      calloc.free(p);
    }
  }
}

final _w = _Win32();
