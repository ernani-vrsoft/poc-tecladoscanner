import 'package:flutter/material.dart';
import 'package:leitor_dispositivos/leitor_dispositivos.dart';

const corTeclado = Color(0xFF1E66D0);
const corScanner = Color(0xFFE07B00);
const corSerial = Colors.blueGrey;

/// SCANNER para os aparelhos marcados; o resto é TECLADO (HID) ou SERIAL.
class EtiquetaOrigem extends StatelessWidget {
  const EtiquetaOrigem({super.key, required this.scanner, required this.tipo});

  final bool scanner;
  final TipoDispositivo tipo;

  @override
  Widget build(BuildContext context) {
    final (cor, texto) = scanner
        ? (corScanner, 'SCANNER')
        : tipo == TipoDispositivo.serial
        ? (corSerial, 'SERIAL')
        : (corTeclado, 'TECLADO');
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Text(
        texto,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
