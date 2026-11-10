/// Diz se cada tecla veio de um teclado ou de um scanner.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

enum TipoOrigem { desconhecido, teclado, scanner }

enum MotivoClassificacao {
  nenhum('nada indicou scanner'),
  fabricante('fabricante (VID) de scanner'),
  nome('nome do aparelho'),
  aprendido('aprendido antes'),
  velocidade('rajada rápida + Enter'),
  regularidade('rajada de ritmo constante + Enter'),
  semAparelho('tecla injetada (sem aparelho físico)'),
  serial('porta serial'),
  portaEmUso('porta serial aberta por outro programa');

  const MotivoClassificacao(this.descricao);
  final String descricao;
}

class Aparelho {
  const Aparelho({
    required this.id,
    required this.tipo,
    required this.motivo,
    required this.vid,
    required this.pid,
    required this.conectado,
    required this.nome,
    required this.caminho,
  });

  final int id;
  final TipoOrigem tipo;
  final MotivoClassificacao motivo;
  final int vid;
  final int pid;
  final bool conectado;
  final String nome;
  final String caminho;

  String get vidPid =>
      '${vid.toRadixString(16).padLeft(4, '0')}:${pid.toRadixString(16).padLeft(4, '0')}';
}

class OrigemTecla {
  const OrigemTecla(this.tipo, this.aparelho);
  final TipoOrigem tipo;

  /// Aparelho de onde a tecla veio, se a lib viu a tecla.
  final Aparelho? aparelho;

  bool get ehScanner => tipo == TipoOrigem.scanner;
}

class LeituraSerial {
  const LeituraSerial(this.texto, this.aparelho);
  final String texto;
  final Aparelho? aparelho;
}

abstract final class ScannerInput {
  static bool _ativo = false;

  /// Inicia a escuta. [arquivoEstado] guarda os scanners aprendidos por
  /// comportamento. Retorna 0 se ok.
  static int iniciar({String? arquivoEstado}) {
    if (_ativo) return 0;
    final caminho = arquivoEstado?.toNativeUtf8();
    try {
      final r = _iniciar(caminho ?? nullptr);
      _ativo = r == 0;
      return r;
    } finally {
      if (caminho != null) calloc.free(caminho);
    }
  }

  static void parar() {
    if (!_ativo) return;
    _parar();
    _ativo = false;
  }

  /// Origem do [evento]. Chame uma única vez por KeyDownEvent/KeyRepeatEvent:
  /// a consulta consome o registro da tecla na lib.
  static OrigemTecla origemDa(KeyEvent evento) {
    if (evento is KeyUpEvent) return const OrigemTecla(TipoOrigem.desconhecido, null);
    final r = _origem(evento.physicalKey.usbHidUsage & 0xFFFF);
    final tipo = TipoOrigem.values[r.tipo];
    if (r.aparelho < 0) return OrigemTecla(tipo, null);
    final ap = aparelhos().where((a) => a.id == r.aparelho).firstOrNull;
    return OrigemTecla(tipo, ap);
  }

  static List<Aparelho> aparelhos() {
    const max = 64;
    final buf = calloc<_SiAparelho>(max);
    try {
      final n = _aparelhos(buf, max);
      return [
        for (var i = 0; i < n; i++)
          Aparelho(
            id: buf[i].id,
            tipo: TipoOrigem.values[buf[i].tipo],
            motivo: MotivoClassificacao.values[buf[i].motivo],
            vid: buf[i].vid,
            pid: buf[i].pid,
            conectado: buf[i].conectado == 1,
            nome: _texto(buf[i].nome, 128),
            caminho: _texto(buf[i].caminho, 256),
          ),
      ];
    } finally {
      calloc.free(buf);
    }
  }

  /// Leituras completas dos scanners seriais desde a última chamada.
  /// Elas não passam pelo teclado: chame periodicamente (ex.: a cada 50 ms).
  static List<LeituraSerial> leiturasSeriais() {
    final buf = calloc<_SiLeitura>();
    final saida = <LeituraSerial>[];
    try {
      List<Aparelho>? lista;
      while (_proximaLeitura(buf) == 1) {
        lista ??= aparelhos();
        final id = buf.ref.aparelho;
        saida.add(
          LeituraSerial(_texto(buf.ref.texto, 512), lista.where((a) => a.id == id).firstOrNull),
        );
      }
    } finally {
      calloc.free(buf);
    }
    return saida;
  }

  static void esquecerAprendidos() => _esquecer();

  static String diagnostico() => _diagnostico().toDartString();
}

String _texto(Array<Char> a, int tam) {
  final bytes = <int>[];
  for (var i = 0; i < tam && a[i] != 0; i++) {
    bytes.add(a[i] & 0xFF);
  }
  return const Utf8Decoder(allowMalformed: true).convert(bytes);
}

// ---------------------------------------------------------------------------
// Ligação com a lib nativa (espelha src/scanner_input.h)
// ---------------------------------------------------------------------------
final class _SiAparelho extends Struct {
  @Int32()
  external int id;
  @Int32()
  external int tipo;
  @Int32()
  external int motivo;
  @Int32()
  external int vid;
  @Int32()
  external int pid;
  @Int32()
  external int conectado;
  @Array(128)
  external Array<Char> nome;
  @Array(256)
  external Array<Char> caminho;
}

final class _SiLeitura extends Struct {
  @Int32()
  external int aparelho;
  @Array(512)
  external Array<Char> texto;
}

final class _SiOrigem extends Struct {
  @Int32()
  external int tipo;
  @Int32()
  external int aparelho;
}

final DynamicLibrary _lib = Platform.isWindows
    ? DynamicLibrary.open('scanner_input.dll')
    : DynamicLibrary.open('libscanner_input.so');

final _iniciar = _lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
  'si_iniciar',
);
final _parar = _lib.lookupFunction<Void Function(), void Function()>('si_parar');
final _origem = _lib.lookupFunction<_SiOrigem Function(Uint32), _SiOrigem Function(int)>(
  'si_origem_da_tecla',
);
final _aparelhos = _lib
    .lookupFunction<
      Int32 Function(Pointer<_SiAparelho>, Int32),
      int Function(Pointer<_SiAparelho>, int)
    >('si_aparelhos');
final _esquecer = _lib.lookupFunction<Void Function(), void Function()>('si_esquecer_aprendidos');
final _diagnostico = _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
  'si_diagnostico',
);
final _proximaLeitura = _lib
    .lookupFunction<Int32 Function(Pointer<_SiLeitura>), int Function(Pointer<_SiLeitura>)>(
      'si_proxima_leitura',
    );
