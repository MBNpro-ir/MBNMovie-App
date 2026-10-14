#ifndef MBN_APP_BUNDLE_H_
#define MBN_APP_BUNDLE_H_
#include <windows.h>
#include <string>
#include <vector>
namespace mbn_runner {
inline std::wstring ExecutableDirectory() {
  std::vector<wchar_t> path(32768);
  const DWORD count = ::GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (count == 0 || count >= path.size()) return {};
  const std::wstring full(path.data(), count);
  const auto separator = full.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring{} : full.substr(0, separator);
}
inline bool BundleFileExists(const std::wstring& directory, const wchar_t* relative) {
  const DWORD attrs = ::GetFileAttributesW((directory + L"\\" + relative).c_str());
  return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}
inline bool BundleLooksComplete(const std::wstring& directory) {
  if (directory.empty()) return false;
  return BundleFileExists(directory, L"flutter_windows.dll") &&
         BundleFileExists(directory, L"data\\icudtl.dat") &&
         (BundleFileExists(directory, L"data\\flutter_assets\\AssetManifest.bin") ||
          BundleFileExists(directory, L"data\\flutter_assets\\AssetManifest.json"));
}
}  // namespace mbn_runner
#endif
