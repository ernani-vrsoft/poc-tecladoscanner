import 'dart:io';

import 'package:flutter/material.dart';
import 'package:leitor_dispositivos/leitor_dispositivos.dart';

import '../scanners.dart';
import 'linha_dispositivo.dart';

/// Lista as portas seriais e os aparelhos HID para o usuário marcar os scanners.
class PainelDispositivos extends StatelessWidget {
  const PainelDispositivos({super.key, required this.leitor, required this.scanners});

  final LeitorDispositivos leitor;
  final Scanners scanners;

  @override
  Widget build(BuildContext context) {
    final d = leitor;
    final todos = d.dispositivos;
    Widget linha(Dispositivo x) =>
LinhaDispositivo(
      dispositivo: x,
      scanner: scanners.contem(x.id),
      onMarcar: (v) => scanners.marcar(x.id, v),
    );
    final seriais = todos.where((x) => x.tipo == TipoDispositivo.serial).map(linha).toList();
    final hids = todos.where((x) => x.tipo == TipoDispositivo.hid).map(linha).toList();

    return Card(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Marque quais aparelhos são scanner',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Faça uma leitura: o aparelho que recebeu os dados acende em verde.',
            style: TextStyle(fontSize: 12),
          ),
          if (d.erroHid != null)
            Text(d.erroHid!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          const Divider(height: 24),
          ..._secaoSerial(d, seriais),
          const Divider(height: 24),
          ..._secaoHid(d, hids),
        ],
      ),
    );
  }

  List<Widget> _secaoSerial(LeitorDispositivos d, List<Widget> linhas) => [
    Row(
      children: [
        const Icon(Icons.cable, size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Portas seriais (COM)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Text('Detectar', style: TextStyle(fontSize: 12)),
        Switch(value: d.escutarTodasSeriais, onChanged: (v) => d.escutarTodasSeriais = v),
      ],
    ),
    Text(
      d.escutarTodasSeriais
          ? 'Todas as portas abertas para detectar atividade. Desligue ao terminar.'
          : 'Só as portas marcadas como scanner ficam abertas. Ligue "Detectar" para ver as outras recebendo dados.',
      style: const TextStyle(fontSize: 11, color: Colors.grey),
    ),
    if (linhas.isEmpty) const _Vazio('Nenhuma porta serial encontrada.'),
    ...linhas,
  ];

  List<Widget> _secaoHid(LeitorDispositivos d, List<Widget> linhas) => [
    const Row(
      children: [
        Icon(Icons.keyboard, size: 18),
        SizedBox(width: 8),
        Text('USB HID (teclados e scanners)', style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
    const Text(
      'Para leituras HID, deixe a janela do app em foco. Sem foco o aparelho '
      'ainda acende, mas o texto vai para o outro programa.',
      style: TextStyle(fontSize: 11, color: Colors.grey),
    ),
    if (Platform.isWindows)
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Scanner não digita no app', style: TextStyle(fontSize: 13)),
        subtitle: const Text(
          'As teclas dos scanners marcados viram só leitura.',
          style: TextStyle(fontSize: 11),
        ),
        value: scanners.bloquear,
        onChanged: (v) => scanners.bloquear = v,
      ),
    if (linhas.isEmpty) const _Vazio('Nenhum teclado encontrado.'),
    ...linhas,
  ];
}

class _Vazio extends StatelessWidget {
  const _Vazio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(texto, style: const TextStyle(color: Colors.grey)),
  );
}
