# Lib nativa scanner_input: núcleo comum + parte do sistema.
cmake_minimum_required(VERSION 3.10)

project(scanner_input_library VERSION 0.1.0 LANGUAGES C)

if (WIN32)
  set(SI_PLATAFORMA "si_windows.c")
else()
  set(SI_PLATAFORMA "si_linux.c")
endif()

add_library(scanner_input SHARED
  "si_nucleo.c"
  "${SI_PLATAFORMA}"
)

set_target_properties(scanner_input PROPERTIES
  PUBLIC_HEADER scanner_input.h
  OUTPUT_NAME "scanner_input"
  C_STANDARD 11
)

if (WIN32)
  target_link_libraries(scanner_input PRIVATE hid)
else()
  find_package(Threads REQUIRED)
  target_link_libraries(scanner_input PRIVATE Threads::Threads m)
  target_compile_options(scanner_input PRIVATE -fvisibility=hidden -Wall -Wextra)
endif()
