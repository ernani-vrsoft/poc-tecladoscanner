/// Dados fixos de um aparelho, lidos uma vez quando ele aparece.
class InfoAparelho {
  final String id;
  final String nome;
  final String descricao;
  final String vidPid;

  const InfoAparelho(this.id, this.nome, this.descricao, this.vidPid);
}

/// Origem de aparelhos (portas seriais ou teclados HID). O leitor consulta
/// o estado e é avisado pelos callbacks.
abstract class Fonte {
  Fonte({required this.mudou, required this.dados});

  /// A lista de aparelhos, os abertos ou os erros mudaram.
  final void Function() mudou;

  /// Chegou algo do aparelho (para mostrar atividade).
  final void Function(String id) dados;

  Map<String, InfoAparelho> get presentes;
  Set<String> get escutando;
  Map<String, String> get erros;

  void iniciar();
  void parar();
}

/// Ordena COM2 antes de COM10.
int compararNomes(String a, String b) {
  final na = RegExp(r'^(.*?)(\d+)$').firstMatch(a);
  final nb = RegExp(r'^(.*?)(\d+)$').firstMatch(b);
  if (na != null && nb != null && na[1] == nb[1]) {
    return int.parse(na[2]!).compareTo(int.parse(nb[2]!));
  }
  return a.compareTo(b);
}
