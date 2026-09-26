# Local patch (upstream 9.5.9)

Source: https://github.com/781flyingdutchman/background_downloader

Pinned to the newest release compatible with this app's Dart 3.12 SDK.
Android notification artwork uses a bounded, app-private cached cover named in
task metadata and notifications remain silent. Native transfer and pause/resume
implementations are unchanged. Android and desktop queue reconfiguration call
`advanceQueue()` / `_advanceQueue()` so resuming a fully held queue starts its
existing tasks without requiring another enqueue.
Keep the upstream LICENSE. Reapply/review this patch when upgrading.
