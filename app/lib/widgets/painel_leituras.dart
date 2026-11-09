import 'package:flutter/material.dart';
import 'package:leitor_dispositivos/leitor_dispositivos.dart';

import '../scanners.dart';
import 'etiqueta_origem.dart';
import 'linha_leitura.dart';

/// O que está sendo digitado agora e as leituras completas, mais recentes no topo.
class PainelLeituras extends StatelessWidget {
  const PainelLeituras({
    super.key,
    required this.leitor,
    required this.scanners,
    required this.leituras,
    required this.onLimpar,
  });

  final LeitorDispositivos leitor;
  final Scanners scanners;
  final List<LeituraClassificada> leituras;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    final digitando = leitor.digitando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Digitando agora (com o app em foco):',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (digitando.isEmpty)
          const Text('—', style: TextStyle(color: Colors.grey))
        else
          ...digitando.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  EtiquetaOrigem(scanner: scanners.contem(e.key), tipo: TipoDispositivo.hid),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${e.value}▌',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text('Leituras:', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(onPressed: onLimpar, child: const Text('Limpar lista')),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: leituras.length,
            itemBuilder: (_, i) => LinhaLeitura(leitura: leituras[i]),
          ),
        ),
      ],
    );
  }
}
