#ifndef MBN_WEB_PLAYER_HANDOFF_H_
#define MBN_WEB_PLAYER_HANDOFF_H_
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>

inline bool DecodeWebPlaybackUrl(const std::string& link, const std::string& scheme,
                                 std::string* output) {
  const std::string prefix = scheme + "://vlc?url=";
  if (link.size() > 32768 || link.compare(0, prefix.size(), prefix) != 0) return false;
  std::string decoded;
  const auto value = link.substr(prefix.size());
  auto hex = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  for (size_t i = 0; i < value.size(); ++i) {
    unsigned char c = static_cast<unsigned char>(value[i]);
    if (c == '%') {
      if (i + 2 >= value.size() || hex(value[i+1]) < 0 || hex(value[i+2]) < 0) return false;
      c = static_cast<unsigned char>((hex(value[i+1]) << 4) | hex(value[i+2]));
      i += 2;
    } else if (c == '+') {
      c = ' ';
    }
    if (c <= 32 || c == 127 || c == '"' || c == '\\') return false;
    decoded += static_cast<char>(c);
  }
  const std::string anime = "https://anime.mbnpro.ir/api/web/media?ticket=";
  const std::string movie = "https://movie.mbnpro.ir/api/web/media?ticket=";
  if (decoded.compare(0, anime.size(), anime) != 0 &&
      decoded.compare(0, movie.size(), movie) != 0) return false;
  if (decoded.back() == '=' || decoded.find('#') != std::string::npos) return false;
  *output = decoded;
  return true;
}

inline bool LaunchWebVlc(const std::string& link, const std::string& scheme) {
  std::string url;
  if (!DecodeWebPlaybackUrl(link, scheme, &url)) return false;
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url.data(),
                                    static_cast<int>(url.size()), nullptr, 0);
  if (length <= 0) return false;
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url.data(),
                      static_cast<int>(url.size()), &wide[0], length);
  const std::wstring argument = L"\"" + wide + L"\"";
  for (const wchar_t* env : {L"ProgramFiles", L"ProgramFiles(x86)"}) {
    wchar_t folder[32768];
    const DWORD count = GetEnvironmentVariableW(env, folder, 32768);
    if (!count || count >= 32768) continue;
    const std::wstring executable = std::wstring(folder) + L"\\VideoLAN\\VLC\\vlc.exe";
    if (GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES) continue;
    // A fixed executable and one quoted URL. No cmd.exe or shell expansion.
    const auto result = ShellExecuteW(nullptr, L"open", executable.c_str(),
                                     argument.c_str(), nullptr, SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(result) > 32;
  }
  MessageBoxW(nullptr, L"VLC روی ویندوز نصب نیست. آن را از videolan.org نصب کنید.",
              L"MBN — VLC", MB_OK | MB_ICONINFORMATION);
  return false;
}
#endif
