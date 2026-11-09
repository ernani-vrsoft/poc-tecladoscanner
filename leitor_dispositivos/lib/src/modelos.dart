enum TipoDispositivo {
  /// Porta serial (COMx, /dev/ttyACM0), inclusive USB-COM.
  serial,

  /// Aparelho que digita como teclado (USB HID).
  hid,
}

/// Parâmetros das portas seriais. O padrão (9600 8N1) é o de fábrica da
/// maioria dos leitores em modo serial / USB-COM.
class ConfigSerial {
  final int baudRate;
  final int bits;
  final int paridade; // SerialPortParity
  final int stopBits;

  const ConfigSerial({
    this.baudRate = 9600,
    this.bits = 8,
    this.paridade = 0,
    this.stopBits = 1,
  });
}

/// Aparelho de entrada presente no sistema.
class Dispositivo {
  /// Serial: o nome da porta. HID: o ID único do aparelho, que depende da
  /// porta USB (dois aparelhos iguais em portas diferentes têm IDs diferentes).
  final String id;
  final TipoDispositivo tipo;

  /// Nome amigável: "COM3", "Honeywell 1250g"...
  final String nome;

  /// Descrição do sistema, ex: "USB Serial Device (COM3)".
  final String descricao;

  /// VID:PID em hexadecimal, quando o sistema informa.
  final String vidPid;

  /// Sendo escutado agora. HID: sempre. Serial: só as portas pedidas em
  /// [LeitorDispositivos.escutarSeriais] ou com `escutarTodasSeriais` ligado.
  final bool escutando;

  /// Teclas deste aparelho não chegam ao resto do app (só ao leitor).
  final bool bloqueado;

  /// Recebeu dados há pouco tempo.
  final bool recebendo;
  final DateTime? ultimoDado;

  /// Por que não está sendo escutado (porta em uso, sem permissão...).
  final String? erro;

  const Dispositivo({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.descricao,
    required this.vidPid,
    required this.escutando,
    required this.bloqueado,
    required this.recebendo,
    required this.ultimoDado,
    required this.erro,
  });
}

/// Leitura completa. Serial: terminou em CR/LF ou numa pausa curta.
/// HID: terminou no Enter.
class Leitura {
  final String dispositivoId;
  final TipoDispositivo tipo;
  final String nome;
  final String texto;
  final DateTime hora;

  Leitura({
    required this.dispositivoId,
    required this.tipo,
    required this.nome,
    required this.texto,
  }) : hora = DateTime.now();
}
