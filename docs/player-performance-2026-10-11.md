# Player persistence and control shading validation

Native Windows debug test on this workstation, synthetic local H.264 1080p30,
D3D11VA-copy hardware decoding. The real PlayerScreen and five-second progress
saves ran while six preferences were written in bursts every two seconds.
Preferences were isolated in a temporary directory, not the user account.

| Data size | Before max event-loop gap | After MBNMovie | After MBNime |
|---|---:|---:|---:|
| 32 KiB | 12.0 ms | 11.1 ms | 16.0 ms |
| 2 MiB | 47.7 ms | 16.6 ms | 17.0 ms |

Both after runs: no decoder drops, no build/raster frames above 16.7 ms,
no player errors. One output drop occurred during startup in both the baseline
and corrected runs; the counter did not increase during either measured phase.

The Windows 2.4.1 preferences implementation encoded JSON and wrote the full
file synchronously on the UI isolate for each mutation. The local patch encodes
in a worker isolate, uses asynchronous disk I/O, and serializes snapshots.
Save/sync cadence, keys, and playback decoder settings are unchanged.
The six-write burst takes longer overall with worker scheduling; it no longer
blocks the UI for its duration. Regression tests cover concurrent mutations,
last-write ordering, remove/clear, disk reload, and recovery after failure.

Control shading uses two bounded gradients with safe-area insets. Pixel tests
cover 320x180, 844x390, 390x844, and 1920x1080: top/bottom remain shaded and the
middle is clear. Pointer hit testing remains functional.

A second controlled run added a phase without synthetic write bursts.
MBNMovie timer gaps: 17.6 ms without stress, 13.8 ms with 2 MiB persistence;
MBNime: 13.1 ms without stress, 17.7 ms with 2 MiB persistence. Timer callback
spacing is not video pause duration. Assertions confirmed zero decoder drops
and no increase in output-frame drops throughout all three playback phases.
The 8 ms diagnostic timer is subject to normal Windows scheduling.

These measurements identify and remove a periodic UI stall. They do not prove
all network-, codec-, GPU-, or device-specific playback stalls are eliminated,
and are not battery measurements or physical iPhone/Android/TV validation.

Reproduce native test with a >=60-second local H.264 file:

```
flutter test integration_test/windows_player_performance_test.dart -d windows --dart-define=MBN_QA_MEDIA=<file>
```
