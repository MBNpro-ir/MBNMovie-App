# MBNime media_kit patch

This directory vendors `media_kit` 1.2.6 from pub.dev under its MIT license.

The only behavioral change is the merged upstream hot-restart fix from
media-kit/media-kit pull request #1416 (commit
`44ba261c463f5e2cef926d35438a95ee63cc5cf9`). It clears stale mpv wakeup
callbacks before sending `quit`, preventing Flutter 3.38+ / Dart 3.10+ from
aborting with `Callback invoked after it has been deleted` during hot restart.
