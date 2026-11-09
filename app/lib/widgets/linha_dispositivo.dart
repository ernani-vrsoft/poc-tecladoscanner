import 'package:flutter/material.dart';
import 'package:leitor_dispositivos/leitor_dispositivos.dart';

/// Um aparelho: luz de atividade, nome, detalhes e a caixa "Scanner".
class LinhaDispositivo extends StatelessWidget {
  const LinhaDispositivo({
    super.key,
    required this.dispositivo,
    required this.scanner,
    required this.onMarcar,
  });

  final Dispositivo dispositivo;
  final bool scanner;
  final ValueChanged<bool> onMarcar;

  @override
  Widget build(BuildContext context) {
    final x = dispositivo;
    final detalhes = [
      if (x.vidPid.isNotEmpty) x.vidPid,
      if (x.descricao.isNotEmpty) x.descricao,
    ].join(' · ');
    final estado = x.recebendo
        ? 'Recebendo dados'
        : x.escutando
        ? 'Escutando'
        : 'Fechada';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Tooltip(
            message: estado,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: x.recebendo
                    ? Colors.green
                    : x.escutando
                    ? Colors.grey.shade400
                    : Colors.transparent,
                border: Border.all(color: Colors.grey.shade500),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  x.nome,
                  style: TextStyle(fontWeight: x.recebendo ? FontWeight.bold : FontWeight.normal),
                ),
                if (detalhes.isNotEmpty)
                  Text(
                    detalhes,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (x.erro != null)
                  Text(x.erro!, style: const TextStyle(fontSize: 11, color: Colors.red)),
              ],
            ),
          ),
          const Text('Scanner', style: TextStyle(fontSize: 12)),
          Checkbox(value: scanner, onChanged: (v) => onMarcar(v ?? false)),
        ],
      ),
    );
  }
}
