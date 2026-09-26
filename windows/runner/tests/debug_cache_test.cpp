#include "../media_kit_debug_cache.h"
#include <filesystem>
#include <fstream>
#include <iostream>

int main() {
  const auto directory = std::filesystem::temp_directory_path() /
      (L"mbnmovie-debug-cache-test-" + std::to_wstring(GetCurrentProcessId()));
  // Refuse to touch an existing directory.
  if (!std::filesystem::create_directory(directory)) return 1;
  const auto stale = directory / L"com.alexmercerind.media_kit.NativeReferenceHolder.123";
  const auto other = directory / L"com.alexmercerind.media_kit.NativeReferenceHolder.456";
  std::ofstream(stale) << "1050906494064";
  std::ofstream(other) << "live-process-pointer";
  const bool removed = ClearMediaKitDebugCache(directory.wstring(), 123);
  const bool isolated = !std::filesystem::exists(stale) && std::filesystem::exists(other);
  const bool absent = ClearMediaKitDebugCache(directory.wstring(), 123);
  std::filesystem::create_directory(stale);
  const bool failsSafely = !ClearMediaKitDebugCache(directory.wstring(), 123);
  std::filesystem::remove(stale);
  std::filesystem::remove(other);
  std::filesystem::remove(directory);
  if (!removed || !isolated || !absent || !failsSafely) return 2;
  std::cout << "PASS: stale pointer removed, other PID preserved, absent cache accepted, invalid target rejected\n";
  return 0;
}
