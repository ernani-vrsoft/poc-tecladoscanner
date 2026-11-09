#include "leitor_dispositivos_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <vector>

namespace leitor_dispositivos {

namespace {

constexpr size_t kMaxPendentes = 256;
constexpr BYTE kShift = 1, kCtrl = 2, kAlt = 4;
constexpr UINT kNaoMudarEstado = 0x4;  // ToUnicodeEx: não mexe na tecla morta

LeitorDispositivosPlugin* g_plugin = nullptr;

LRESULT CALLBACK GetMsgProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && wparam == PM_REMOVE && g_plugin) {
    g_plugin->Tratar(reinterpret_cast<MSG*>(lparam));
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

std::string Utf8(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                              nullptr, 0, nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), s.data(),
                      n, nullptr, nullptr);
  return s;
}

BYTE BitModificador(USHORT vkey) {
  switch (vkey) {
    case VK_SHIFT: return kShift;
    case VK_CONTROL: return kCtrl;
    case VK_MENU: return kAlt;
    default: return 0;
  }
}

}  // namespace

void LeitorDispositivosPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<LeitorDispositivosPlugin>(registrar));
}

LeitorDispositivosPlugin::LeitorDispositivosPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  g_plugin = this;
  hook_ = SetWindowsHookExW(WH_GETMESSAGE, GetMsgProc, nullptr,
                            GetCurrentThreadId());

  eventos_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "leitor_dispositivos/teclado",
      &flutter::StandardMethodCodec::GetInstance());
  eventos_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     sink)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            sink_ = std::move(sink);
            Escutar();
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            Parar();
            return nullptr;
          }));

  comandos_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "leitor_dispositivos",
      &flutter::StandardMethodCodec::GetInstance());
  comandos_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "bloquear") {
          result->NotImplemented();
          return;
        }
        bloqueados_.clear();
        if (const auto* lista = std::get_if<flutter::EncodableList>(call.arguments())) {
          for (const auto& v : *lista) {
            if (const auto* s = std::get_if<std::string>(&v)) bloqueados_.insert(*s);
          }
        }
        result->Success();
      });
}

LeitorDispositivosPlugin::~LeitorDispositivosPlugin() {
  Parar();
  if (hook_) UnhookWindowsHookEx(hook_);
  if (g_plugin == this) g_plugin = nullptr;
}

// O Raw Input é registrado só quando o Dart começa a escutar: no registro do
// plugin a view ainda não foi colocada dentro da janela de topo.
void LeitorDispositivosPlugin::Escutar() {
  HWND view = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
  HWND topo = view ? GetAncestor(view, GA_ROOT) : nullptr;
  // INPUTSINK: recebe WM_INPUT também sem foco, para mostrar atividade.
  RAWINPUTDEVICE rid{0x01, 0x06, RIDEV_INPUTSINK, topo};
  if (!topo || !RegisterRawInputDevices(&rid, 1, sizeof(rid))) {
    Emitir("erro", "", "Raw Input: não foi possível registrar os teclados");
  }
}

void LeitorDispositivosPlugin::Parar() {
  RAWINPUTDEVICE rid{0x01, 0x06, RIDEV_REMOVE, nullptr};
  RegisterRawInputDevices(&rid, 1, sizeof(rid));
  sink_.reset();
  fila_.clear();
}

void LeitorDispositivosPlugin::Tratar(MSG* m) {
  if (!sink_) return;
  switch (m->message) {
    case WM_INPUT:
      TratarRawInput(m);
      break;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      TratarTeclaDesce(m);
      break;
    case WM_KEYUP:
    case WM_SYSKEYUP:
      if (soltas_bloqueadas_.erase(static_cast<USHORT>(m->wParam))) {
        m->message = WM_NULL;
      }
      break;
    case WM_CHAR:
      TratarCaractere(static_cast<wchar_t>(m->wParam));
      break;
  }
}

void LeitorDispositivosPlugin::TratarRawInput(MSG* m) {
  RAWINPUT ri{};
  UINT tam = sizeof(ri);
  UINT lidos = GetRawInputData(reinterpret_cast<HRAWINPUT>(m->lParam), RID_INPUT,
                               &ri, &tam, sizeof(RAWINPUTHEADER));
  if (lidos == static_cast<UINT>(-1) || lidos == 0 ||
      ri.header.dwType != RIM_TYPEKEYBOARD) {
    return;
  }
  const RAWKEYBOARD& kb = ri.data.keyboard;
  if (kb.VKey == 0xFF) return;  // tecla "falsa" gerada pelo Windows

  HANDLE dev = ri.header.hDevice;
  bool solta = (kb.Flags & RI_KEY_BREAK) != 0;
  if (BYTE bit = BitModificador(kb.VKey)) {
    mods_[dev] = solta ? (mods_[dev] & ~bit) : (mods_[dev] | bit);
  }
  if (solta) return;

  std::string id = IdAparelho(dev);
  Emitir("atividade", id);

  // Sem foco a tecla vai para outro programa: não haverá WM_KEYDOWN aqui.
  if (GET_RAWINPUT_CODE_WPARAM(m->wParam) != RIM_INPUT) return;

  // Os WM_INPUT (postados) saem da fila antes dos WM_KEYDOWN (entrada); com a
  // UI ocupada chegam vários seguidos. Guarda na ordem e casa pelo vKey.
  USHORT scan = kb.MakeCode | ((kb.Flags & RI_KEY_E0) ? 0xE000 : 0);
  fila_.push_back({id, kb.VKey, scan, mods_[dev]});
  if (fila_.size() > kMaxPendentes) fila_.pop_front();
}

void LeitorDispositivosPlugin::TratarTeclaDesce(MSG* m) {
  USHORT vkey = static_cast<USHORT>(m->wParam);
  auto it = std::find_if(fila_.begin(), fila_.end(),
                         [vkey](const Pendente& p) { return p.vkey == vkey; });
  if (it == fila_.end()) {
    atual_.clear();
    return;
  }
  Pendente p = *it;
  // As duas filas têm a mesma ordem: o que ficou antes não terá WM_KEYDOWN.
  fila_.erase(fila_.begin(), it + 1);
  atual_ = p.id;

  bool bloquear = bloqueados_.count(p.id) > 0;
  if (vkey == VK_RETURN) {
    Emitir("enter", p.id);
  } else if (vkey == VK_BACK) {
    Emitir("apagar", p.id);
  } else if (bloquear) {
    // A tecla não vai chegar ao TranslateMessage, então não haverá WM_CHAR:
    // converte aqui com os modificadores do próprio aparelho.
    BYTE estado[256] = {};
    if (p.mods & kShift) estado[VK_SHIFT] = 0x80;
    if (p.mods & kCtrl) estado[VK_CONTROL] = 0x80;
    if (p.mods & kAlt) estado[VK_MENU] = 0x80;
    if (GetKeyState(VK_CAPITAL) & 1) estado[VK_CAPITAL] = 0x01;
    wchar_t buf[8];
    int n = ToUnicodeEx(vkey, p.scan, estado, buf, 8, kNaoMudarEstado,
                        GetKeyboardLayout(0));
    std::wstring texto;
    for (int i = 0; i < n; i++) {
      if (buf[i] >= 0x20) texto += buf[i];
    }
    if (!texto.empty()) Emitir("texto", p.id, Utf8(texto));
  }

  if (bloquear) {
    m->message = WM_NULL;
    soltas_bloqueadas_.insert(vkey);
  }
}

void LeitorDispositivosPlugin::TratarCaractere(wchar_t c) {
  if (atual_.empty() || c < 0x20 || c == 0x7F) return;
  if (IS_HIGH_SURROGATE(c)) {
    surrogate_ = c;
    return;
  }
  std::wstring w;
  if (IS_LOW_SURROGATE(c) && surrogate_) w += surrogate_;
  surrogate_ = 0;
  w += c;
  Emitir("texto", atual_, Utf8(w));
}

void LeitorDispositivosPlugin::Emitir(const char* tipo, const std::string& id,
                                   const std::string& texto) {
  if (!sink_) return;
  flutter::EncodableMap e{
      {flutter::EncodableValue("tipo"), flutter::EncodableValue(tipo)},
      {flutter::EncodableValue("id"), flutter::EncodableValue(id)},
  };
  if (!texto.empty()) {
    e[flutter::EncodableValue("texto")] = flutter::EncodableValue(texto);
  }
  sink_->Success(flutter::EncodableValue(e));
}

// O caminho do aparelho, em maiúsculas: único por aparelho e por porta USB.
// É o mesmo ID que o lado Dart monta ao listar os teclados.
std::string LeitorDispositivosPlugin::IdAparelho(HANDLE h) {
  auto it = ids_.find(h);
  if (it != ids_.end()) return it->second;
  std::string id;
  if (!h) {
    id = "SEM-APARELHO";  // tecla injetada por software
  } else {
    UINT tam = 0;
    GetRawInputDeviceInfoW(h, RIDI_DEVICENAME, nullptr, &tam);
    std::vector<wchar_t> buf(tam + 1, 0);
    if (tam && GetRawInputDeviceInfoW(h, RIDI_DEVICENAME, buf.data(), &tam) !=
                   static_cast<UINT>(-1)) {
      std::wstring w(buf.data());
      CharUpperBuffW(w.data(), static_cast<DWORD>(w.size()));
      id = Utf8(w);
    }
    if (id.empty()) id = "DESCONHECIDO";
  }
  ids_[h] = id;
  return id;
}

}  // namespace leitor_dispositivos
