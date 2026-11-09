import 'package:flutter/material.dart';

import '../scanners.dart';
import 'etiqueta_origem.dart';

class LinhaLeitura extends StatelessWidget {
  const LinhaLeitura({super.key, required this.leitura});

  final LeituraClassificada leitura;

  @override
  Widget build(BuildContext context) {
    final l = leitura.leitura;
    String dois(int n) => n.toString().padLeft(2, '0');
    final hora = '${dois(l.hora.hour)}:${dois(l.hora.minute)}:${dois(l.hora.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hora, style: const TextStyle(fontFamily: 'monospace', color: Colors.grey)),
          const SizedBox(width: 8),
          EtiquetaOrigem(scanner: leitura.scanner, tipo: l.tipo),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  l.texto,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
                Text(l.nome, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
