# Tested Windows playback core

libmpv: mpv v0.41.0-1227-ge471496c5, baseline x86_64 build `20261021-git-e471496c56`.
Build recipe and upstream source revisions: https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261021
Player source: https://github.com/mpv-player/mpv/tree/e471496c5
The package wrapper retains its upstream MIT license; the native components have their respective upstream licenses.

Archive SHA256: `efc719eff3dc5954b4a5efc800632808bcec01cc9034940dd14e5eb7fe9ea633`
DLL SHA256: `04e4d27dc385dc18ddd93fbe69c75e635b864f3c6ec53a9122df54c2f7842f4a`

The extracted directory includes the build identifier. Both the archive and extracted DLL are verified, including on incremental builds.
Do not replace this with a moving latest URL or the x86_64-v3 variant.

Validation: compare the same media in an isolated production PlayerScreen with normal Flutter scheduling. The user observed startup stutter with the 2023 core and smooth startup with this build. Check hardware and software modes, subtitle rendering, seeking, pause and Back before changing this pin.
