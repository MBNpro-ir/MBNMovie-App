#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "app_bundle.h"
#include "media_kit_debug_cache.h"
#include "web_player_handoff.h"

namespace {

constexpr wchar_t kWindowTitle[] = L"MBNMovie";
constexpr wchar_t kMutexName[] = L"Local\\MBN_MBNMovie_SingleInstance";
constexpr wchar_t kFlutterWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

void ActivateRunningWindow() {
  // The first process may still be creating its window when the mutex appears.
  for (int attempt = 0; attempt < 100; ++attempt) {
    HWND hwnd = ::FindWindowW(kFlutterWindowClass, kWindowTitle);
    if (hwnd != nullptr) {
      if (::IsIconic(hwnd)) {
        ::ShowWindow(hwnd, SW_RESTORE);
      } else {
        ::ShowWindow(hwnd, SW_SHOW);
      }
      ::SetForegroundWindow(hwnd);
      return;
    }
    ::Sleep(100);
  }
  // The previous instance never published a window (e.g. crashed during
  // startup while still holding the mutex name briefly): tell the user instead
  // of exiting silently so a "nothing happens on second launch" is diagnosable.
  ::MessageBoxW(nullptr,
                L"برنامه در حال اجراست اما پنجره آن یافت نشد. لطفاً از Task Manager پردازش mbnmovie.exe را ببندید و دوباره باز کنید.",
                L"MBNMovie", MB_OK | MB_ICONINFORMATION);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const auto launch_args = GetCommandLineArguments();
  if (launch_args.size() == 2 && launch_args[0] == "--web-player") {
    return LaunchWebVlc(launch_args[1], "mbnmovie-player") ? EXIT_SUCCESS : EXIT_FAILURE;
  }
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, kMutexName);
  if (instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningWindow();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

#ifdef _DEBUG
  if (!PrepareMediaKitDebugProcess()) {
    ::OutputDebugStringW(L"MBNMovie: cannot reset media_kit debug pointer cache.\n");
    return EXIT_FAILURE;
  }
#endif

  const auto bundle_directory = mbn_runner::ExecutableDirectory();
  if (!mbn_runner::BundleLooksComplete(bundle_directory)) {
    ::MessageBoxW(nullptr,
                  L"فایل‌های برنامه ناقص است. لطفاً کل پوشه MBNMovie (نه فقط mbnmovie.exe) را از فایل ZIP خارج کنید و دوباره اجرا کنید.",
                  L"MBNMovie", MB_OK | MB_ICONWARNING);
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(bundle_directory + L"\\data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
