#include <windows.h>
#include <shellapi.h>
#include <filesystem>
#include <fstream>
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
#ifdef FIXTURE_FAIL
  // Valid x64 PE that fails to start, without an OS compatibility dialog.
  return 1;
#endif
  int argc;
  auto argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argc == 3 && std::wstring(argv[1]) == L"--wait") {
    for (int i = 0; i < 600; ++i) {
      if (std::filesystem::exists(argv[2])) { LocalFree(argv); return 0; }
      Sleep(100);
    }
    LocalFree(argv); return 1;
  }
  LocalFree(argv);
  wchar_t executable[32768];
  GetModuleFileNameW(nullptr, executable, 32768);
  const auto root = std::filesystem::path(executable).parent_path();
  std::ofstream marker(root / L"run-marker.txt"); marker << FIXTURE_VERSION; marker.close();
  Sleep(20000);
  return 0;
}
