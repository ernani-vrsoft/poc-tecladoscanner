#ifndef FLUTTER_PLUGIN_LEITOR_DISPOSITIVOS_PLUGIN_H_
#define FLUTTER_PLUGIN_LEITOR_DISPOSITIVOS_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <deque>
#include <map>
#include <memory>
#include <set>
#include <string>

namespace leitor_dispositivos {

// Descobre de qual aparelho veio cada tecla digitada no app, com um hook
// WH_GETMESSAGE só na thread de UI: vê WM_INPUT (aparelho) e WM_KEYDOWN/
// WM_CHAR (caractere já convertido pelo Windows) na ordem em que saem da fila,
// antes do Flutter. O redispatch da engine usa SendMessage e não passa aqui.
class LeitorDispositivosPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit LeitorDispositivosPlugin(flutter::PluginRegistrarWindows* registrar);
  ~LeitorDispositivosPlugin() override;

  LeitorDispositivosPlugin(const LeitorDispositivosPlugin&) = delete;
  LeitorDispositivosPlugin& operator=(const LeitorDispositivosPlugin&) = delete;

  void Tratar(MSG* m);

 private:
  struct Pendente {
    std::string id;
    USHORT vkey;
    USHORT scan;
    BYTE mods;
  };

  void Escutar();
  void Parar();
  void TratarRawInput(MSG* m);
  void TratarTeclaDesce(MSG* m);
  void TratarCaractere(wchar_t c);
  void Emitir(const char* tipo, const std::string& id,
              const std::string& texto = "");
  std::string IdAparelho(HANDLE h);

  flutter::PluginRegistrarWindows* registrar_;
  HHOOK hook_ = nullptr;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> eventos_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> comandos_;

  std::deque<Pendente> fila_;
  std::map<HANDLE, std::string> ids_;
  std::map<HANDLE, BYTE> mods_;
  std::string atual_;
  wchar_t surrogate_ = 0;
  std::set<std::string> bloqueados_;
  std::set<USHORT> soltas_bloqueadas_;
};

}  // namespace leitor_dispositivos

#endif  // FLUTTER_PLUGIN_LEITOR_DISPOSITIVOS_PLUGIN_H_
