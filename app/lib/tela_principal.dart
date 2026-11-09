import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leitor_dispositivos/leitor_dispositivos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scanners.dart';
import 'widgets/painel_dispositivos.dart';
import 'widgets/painel_leituras.dart';

const _maxLeituras = 200;

/// Cria o leitor e a configuração de scanners e acumula as leituras.
class TelaPrincipal extends StatefulWidget {
  const TelaPrincipal({super.key});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  LeitorDispositivos? _leitor;
  Scanners? _scanners;
  StreamSubscription<Leitura>? _sub;
  final List<LeituraClassificada> _leituras = [];

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    final leitor = LeitorDispositivos();
    final scanners = Scanners(prefs, leitor);
    leitor.addListener(_redesenhar);
    scanners.addListener(_redesenhar);
    _sub = leitor.leituras.listen((l) {
      setState(() {
        _leituras.insert(0, LeituraClassificada(l, scanners.contem(l.dispositivoId)));
        if (_leituras.length > _maxLeituras) _leituras.removeLast();
      });
    });
    leitor.iniciar();
    setState(() {
      _leitor = leitor;
      _scanners = scanners;
    });
  }

  void _redesenhar() => setState(() {});

  @override
  void dispose() {
    _sub?.cancel();
    _scanners?.dispose();
    _leitor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leitor = _leitor;
    final scanners = _scanners;
    return Scaffold(
      appBar: AppBar(title: const Text('Teclado x Scanner')),
      body: leitor == null || scanners == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 460,
                    child: PainelDispositivos(leitor: leitor, scanners: scanners),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: PainelLeituras(
                      leitor: leitor,
                      scanners: scanners,
                      leituras: _leituras,
                      onLimpar: () => setState(_leituras.clear),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
