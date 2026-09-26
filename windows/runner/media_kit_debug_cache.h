#ifndef RUNNER_MEDIA_KIT_DEBUG_CACHE_H_
#define RUNNER_MEDIA_KIT_DEBUG_CACHE_H_

#include <windows.h>
#include <string>

// media_kit 1.2.6 stores a native pointer in a PID-named temp file for hot
// restart. Windows can reuse that PID after exit, but not the old pointer.
// Call ONLY at native process startup, before creating any Flutter engine;
// never from Dart main(), which also runs on hot restart.
inline bool ClearMediaKitDebugCache(const std::wstring& directory, DWORD pid) {
  const auto file = directory + L"\\com.alexmercerind.media_kit.NativeReferenceHolder." +
                    std::to_wstring(pid);
  if (::DeleteFileW(file.c_str())) return true;
  const auto error = ::GetLastError();
  return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
}

inline bool PrepareMediaKitDebugProcess() {
  wchar_t directory[32768];
  const DWORD length = ::GetTempPathW(32768, directory);
  if (length == 0 || length >= 32768) return false;
  return ClearMediaKitDebugCache(directory, ::GetCurrentProcessId());
}

#endif  // RUNNER_MEDIA_KIT_DEBUG_CACHE_H_
