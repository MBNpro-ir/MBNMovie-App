#include "../app_bundle.h"
#include <iostream>
int main() {
  const auto directory = mbn_runner::ExecutableDirectory();
  if (!mbn_runner::BundleLooksComplete(directory)) return 1;
  wchar_t windows[32768];
  if (!::GetWindowsDirectoryW(windows, 32768) || !::SetCurrentDirectoryW(windows)) return 2;
  if (!mbn_runner::BundleLooksComplete(directory)) return 3;
  if (mbn_runner::BundleLooksComplete(directory + L"\\missing")) return 4;
  if (mbn_runner::BundleLooksComplete(L"")) return 5;
  std::cout << "Bundle remains complete with a different working directory.\n";
  return 0;
}
