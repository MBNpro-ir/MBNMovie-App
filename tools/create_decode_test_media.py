"""Create local synthetic fixtures for android_player_decode_test.dart."""
import pathlib
import subprocess
import sys

directory = pathlib.Path(sys.argv[1]).resolve()
directory.mkdir(parents=True, exist_ok=True)
subtitle = directory / "mbn-legacy.ass"
subtitle.write_text("""[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Vazirmatn,38,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,20,20,30,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:40.00,Default,,0,0,0,,تست پخش Android و زیرنویس فارسی
""", encoding="utf-8")

subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30",
    "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
    "-i", str(subtitle), "-t", "40", "-c:v", "libx264", "-preset", "ultrafast",
    "-crf", "28", "-profile:v", "main", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "96k", "-c:s", "ass",
    "-metadata:s:s:0", "language=fas", str(directory / "mbn-legacy-h264.mkv"),
], check=True)
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24",
    "-i", str(subtitle), "-t", "8", "-c:v", "mpeg1video", "-q:v", "5", "-c:s", "ass",
    str(directory / "mbn-legacy-fallback.mkv"),
], check=True)
