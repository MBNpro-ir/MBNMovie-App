Based on Flutter shared_preferences_windows 2.4.1 (BSD-3-Clause).

Local patch: encode JSON in a worker isolate, use asynchronous disk I/O, and serialize captured preference snapshots. This avoids blocking native Windows playback during periodic progress/sync saves without changing preference keys or the five-second save cadence.
