#include "utils.h"
#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <shellapi.h>
#include <iostream>
void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE* unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) _dup2(_fileno(stdout), 1);
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) _dup2(_fileno(stdout), 2);
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}
std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return {};
  std::vector<std::string> args;
  for (int i = 1; i < argc; i++) args.push_back(Utf8FromUtf16(argv[i]));
  ::LocalFree(argv);
  return args;
}
std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) return {};
  int input_length = static_cast<int>(wcsnlen(utf16_string, 32767));
  int target_length = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, input_length, nullptr, 0, nullptr, nullptr);
  if (target_length <= 0) return {};
  std::string utf8_string(target_length, '\0');
  int converted = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted == 0) return {};
  return utf8_string;
}
