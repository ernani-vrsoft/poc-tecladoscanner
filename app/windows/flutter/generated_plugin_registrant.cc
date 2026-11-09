//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_libserialport/flutter_libserialport_plugin.h>
#include <leitor_dispositivos/leitor_dispositivos_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterLibserialportPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterLibserialportPlugin"));
  LeitorDispositivosPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("LeitorDispositivosPluginCApi"));
}
