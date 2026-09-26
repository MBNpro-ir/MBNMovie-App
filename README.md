# MBNMovie

A Persian RTL Flutter film and series app based on the MBNMovie interface. The home layout, transitions, detail view, player, cast support, search, favorites, history and download manager retain the original Flutter structure. Content is loaded from the new film service using a guest session. The adult section is not available in this edition.

## Run

```sh
flutter pub get
flutter run
flutter build apk --debug --target-platform android-arm64
```

Android application ID: `com.mbn.movie`. Downloads use `Downloads/MBNMovie`.

The former account and updater flows depended on the previous service and release repository, so they are inactive until matching endpoints are available. Playback and download availability depend on the content server's links.
