// MBNMovie transactional bundle updater. No network, shell scripts, elevation or
// recursive deletion. Unknown/user files are preserved; replaced files backed up.
#include <windows.h>
#include <shellapi.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <stdexcept>
#include <algorithm>
namespace fs = std::filesystem;
static void showMessage(const wchar_t* text) {
#ifndef MBNMOVIE_UPDATER_TEST
  MessageBoxW(nullptr, text, L"MBNMovie updater", MB_OK | MB_ICONWARNING);
#else
  OutputDebugStringW(text);
#endif
}

static bool reparse(const fs::path& path) {
  const auto attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT);
}
static void validatePath(const fs::path& path) {
  if (!path.is_absolute() || path == path.root_path()) throw std::runtime_error("Invalid root");
  for (auto current = path; current != current.root_path(); current = current.parent_path()) {
    if (reparse(current)) throw std::runtime_error("Reparse path rejected");
  }
}
static std::wstring quote(const std::wstring& value) {
  // All arguments here are Windows filesystem paths (cannot contain a quote).
  return L"\"" + value + L"\"";
}
static bool launch(const fs::path& root) {
  const auto executable = root / L"mbnmovie.exe";
  auto command = quote(executable.wstring());
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE,
      0, nullptr, root.c_str(), &startup, &process)) return false;
  CloseHandle(process.hThread);
  const bool alive = WaitForSingleObject(process.hProcess, 3000) == WAIT_TIMEOUT;
  CloseHandle(process.hProcess);
  return alive;
}
static void moveFile(const fs::path& from, const fs::path& to) {
  fs::create_directories(to.parent_path());
  for (int attempt = 0; attempt < 100; ++attempt) {
    if (MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_WRITE_THROUGH)) return;
    Sleep(100);
  }
  throw std::runtime_error("File locked or access denied");
}
struct Change { fs::path relative; bool original; bool installed = false; };

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv || argc != 6 || std::wstring(argv[1]) != L"--apply") {
    if (argv) LocalFree(argv);
    showMessage(L"بروزرسانی را از داخل برنامه آغاز کنید.");
    return 2;
  }
  fs::path root, stage, backup;
  HANDLE parent = nullptr;
  bool parentExited = false;
  std::vector<Change> changes;
  try {
    const auto parentId = std::stoul(argv[2]);
    root = fs::absolute(argv[3]).lexically_normal();
    stage = fs::absolute(argv[4]).lexically_normal();
    const fs::path ready = fs::absolute(argv[5]).lexically_normal();
    validatePath(root); validatePath(stage); validatePath(ready);
    if (root == stage || ready.parent_path() != stage.parent_path() ||
        stage.filename() != L"MBNMovie" ||
        !fs::is_regular_file(root / L"mbnmovie.exe") ||
        !fs::is_regular_file(stage / L"mbnmovie.exe") ||
        !fs::is_regular_file(stage / L"data" / L"app.so") ||
        !fs::is_regular_file(stage / L"flutter_windows.dll"))
      throw std::runtime_error("Invalid application bundle");
    parent = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parentId);
    if (!parent) throw std::runtime_error("Parent process unavailable");
    wchar_t processPath[32768]; DWORD size = 32768;
    if (!QueryFullProcessImageNameW(parent, 0, processPath, &size) ||
        !fs::equivalent(fs::path(processPath), root / L"mbnmovie.exe"))
      throw std::runtime_error("Parent does not match installation");
    backup = root / (L".mbnmovie-backup-" + std::to_wstring(GetTickCount64()));
    // Preflight every destination BEFORE acknowledging readiness or closing app.
    for (const auto& entry : fs::recursive_directory_iterator(stage)) {
      if (reparse(entry.path())) throw std::runtime_error("Linked bundle entry");
      if (!entry.is_regular_file()) continue;
      const auto relative = fs::relative(entry.path(), stage);
      validatePath(root / relative);
      if (fs::exists(root / relative) && !fs::is_regular_file(root / relative))
        throw std::runtime_error("Destination is not a regular file");
      changes.push_back({relative, fs::exists(root / relative), false});
    }
    if (changes.empty() || changes.size() > 10000) throw std::runtime_error("Invalid entry count");
    fs::create_directory(backup); // Also verifies target is writable.
    std::ofstream journal(backup / L"journal.txt", std::ios::binary);
    for (const auto& change : changes) journal << change.relative.u8string() << '\n';
    journal.flush();
    if (!journal) throw std::runtime_error("Cannot write journal");
    std::ofstream handshake(ready); handshake << "ready"; handshake.close();
    if (WaitForSingleObject(parent, 30000) != WAIT_OBJECT_0)
      throw std::runtime_error("Application did not close");
    parentExited = true;
    CloseHandle(parent); parent = nullptr;
    // The old updater runs from staging, so even updater.exe is replaceable.
    for (auto& change : changes) {
      const auto destination = root / change.relative;
      if (change.original) moveFile(destination, backup / change.relative);
      fs::create_directories(destination.parent_path());
      change.installed = true;
      fs::copy_file(stage / change.relative, destination);
    }
    if (!launch(root)) throw std::runtime_error("Updated application failed to start");
    std::ofstream(backup / L"SUCCESS") << "Previous files retained for recovery.";
    LocalFree(argv);
    return 0;
  } catch (...) {
    if (parent) CloseHandle(parent);
    if (parentExited) {
      bool restored = true;
      for (auto it = changes.rbegin(); it != changes.rend(); ++it) {
        try {
          const auto original = backup / it->relative;
          const auto destination = root / it->relative;
          if (fs::exists(original)) {
            // Only exact files installed by this operation are removed.
            if (fs::exists(destination)) fs::remove(destination);
            moveFile(original, destination);
          } else if (!it->original && it->installed) {
            fs::remove(destination);
          }
        } catch (...) { restored = false; }
      }
      const bool relaunched = restored && launch(root);
      showMessage(relaunched ?
          L"بروزرسانی ناموفق بود. نسخهٔ قبلی بازیابی و اجرا شد." :
          restored ? L"نسخهٔ قبلی بازیابی شد، اما اجرای خودکار آن ممکن نشد؛ برنامه را دوباره باز کنید." :
          L"بروزرسانی کامل نشد. فایل‌های قبلی در پوشهٔ .mbnmovie-backup کنار برنامه محفوظ‌اند.");
    }
    LocalFree(argv);
    return 1;
  }
}
