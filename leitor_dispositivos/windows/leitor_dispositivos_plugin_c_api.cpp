#include "include/leitor_dispositivos/leitor_dispositivos_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "leitor_dispositivos_plugin.h"

void LeitorDispositivosPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  leitor_dispositivos::LeitorDispositivosPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
