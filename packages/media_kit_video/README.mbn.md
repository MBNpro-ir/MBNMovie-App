# Local patch to media_kit_video 2.0.1

Upstream source and licenses are retained. Android now honors optional width
and height bounds for its render texture, preserving aspect ratio and never
upscaling. Other platforms and unbounded callers retain upstream behavior.
The apps pass the physical display bounds on lightweight Android devices.
This avoids allocating and compositing a full 2K/4K texture on a smaller display;
it does not replace hardware codec support or lower the stream's resolution.

Regression coverage: test/android_video_output_test.dart in each client.

Android 6-9 physical devices use a pre-attached MediaCodec Surface. Older
vendor AImageReader implementations cannot import the GPU's PRIVATE buffers,
causing software fallback; the direct Surface avoids that copy/conversion.
The app enables the NDK decoder lookup for vendors missing constrained-baseline
profile entries. Native ASS/bitmap rendering selects GPU output explicitly.
Unsupported direct codecs recover once to GPU/software, including fatal
conversion logs omitted by media_kit's error stream, and reload only when the
failed media has already been unloaded. New sources reset that fallback.

Physical-device coverage: integration_test/android_production_playback_test.dart
checks the real PlayerScreen, mixed Persian/Latin rendered glyph bounds, 720p,
1080p, seek/pause/exit and unsupported-codec recovery. The separate surface
diagnostic hides default library subtitles so it cannot be mistaken for the
application's production subtitle layer. Emulator tests check compatibility,
not hardware throughput. Original native ASS uses the GPU and can be slower
than the application's plain subtitle layer on old hardware.
