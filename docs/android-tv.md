# Android TV

The existing APK supports phones and TV. At startup the Android bridge detects
UI_MODE_TYPE_TELEVISION or FEATURE_LEANBACK; screen width alone never enables TV.
TV uses landscape immersive mode, launcher banner, a top navigation row, larger
theme text, remote-focus outlines, and overscan padding. Featured slides do not
automatically advance on TV while the user navigates.

Remote controls:
- Catalog: arrows move focus; OK opens the selected card or button.
- Player with controls hidden: left/right seek ten seconds, OK toggles playback,
  up/down reveals the controls and moves focus into them.
- Player with controls visible: arrows navigate controls, OK activates them.
- Back hides visible player controls first; a second Back exits the player.
- System media play/pause is supported. Volume buttons remain system controls.

Device acceptance checks (must be run on an actual Android TV/Google TV):
1. Install the APK without uninstalling existing data; verify the launcher banner.
2. Log in using only the remote and system on-screen keyboard.
3. Navigate home, films, series, favorites, search and drawer destinations.
4. Open a title, choose season/quality and play. Check every player panel via OK.
5. Seek, pause/resume, hide controls, cancel dialogs and exit with Back.
6. Resume saved progress; verify display remains landscape after leaving playback.
7. Test file picker and install-permission/update flow on the TV firmware.
8. Repeat basic navigation on a phone: touch UI must not switch to TV mode.

Widget tests cover remote OK, seek-versus-navigation behavior, and episode layouts
at 960x540 and 1280x720 logical pixels. They do not verify hardware codecs,
OEM file pickers, Android installation, or actual TV remote key mappings.

References:
- https://developer.android.com/training/tv/get-started/create
- https://developer.android.com/training/tv/publishing/checklist
- https://docs.flutter.dev/ui/interactivity/focus
