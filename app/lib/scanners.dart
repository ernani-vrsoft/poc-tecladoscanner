import 'package:flutter/foundation.dart';
import 'package:leitor_dispositivos/leitor_dispositivos.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chaveIds = 'scanners_ids';
const _chaveBloquear = 'scanners_bloquear';

/// Quais aparelhos o app trata como scanner. Fica salvo e é repassado ao
/// leitor: portas seriais dos scanners abertas e, se pedido, teclas dos
/// scanners HID bloqueadas para o resto do app.
class Scanners extends ChangeNotifier {
  Scanners(this._prefs, this._leitor)
    : _ids = (_prefs.getStringList(_chaveIds) ?? const []).toSet(),
      _bloquear = _prefs.getBool(_chaveBloquear) ?? false {
    _aplicar();
  }

  final SharedPreferences _prefs;
  final LeitorDispositivos _leitor;
  final Set<String> _ids;
  bool _bloquear;

  bool contem(String id) => _ids.contains(id);

  void marcar(String id, bool scanner) {
    final mudou = scanner ? _ids.add(id) : _ids.remove(id);
    if (!mudou) return;
    _prefs.setStringList(_chaveIds, _ids.toList());
    _aplicar();
    notifyListeners();
  }

  /// Teclas dos scanners HID não digitam no app: só viram leitura.
  bool get bloquear => _bloquear;
  set bloquear(bool v) {
    if (_bloquear == v) return;
    _bloquear = v;
    _prefs.setBool(_chaveBloquear, v);
    _aplicar();
    notifyListeners();
  }

  void _aplicar() {
    _leitor.escutarSeriais(_ids);
    _leitor.bloquear(_bloquear ? _ids : const <String>[]);
  }
}

/// Leitura com a classificação do app no momento em que chegou.
class LeituraClassificada {
  const LeituraClassificada(this.leitura, this.scanner);

  final Leitura leitura;
  final bool scanner;
}
