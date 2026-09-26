import 'dart:io';
import 'package:flutter/material.dart';
import '../core/player_preferences.dart';
import '../services/external_apps.dart';
import 'default_preference_prompt.dart';

Future<String?> showDownloadPlaybackSheet(BuildContext context) async {
  final allowed = <String>{
    PlaybackPreferenceStore.internalPlayer,
    ExternalVideoPlayer.vlc.name,
    if (Platform.isAndroid) ExternalVideoPlayer.mxPlayer.name,
    if (Platform.isAndroid) ExternalVideoPlayer.mxPlayerPro.name,
  };
  final preferred = await PlaybackPreferenceStore.defaultPlayer();
  if (allowed.contains(preferred)) return preferred;
  if (!context.mounted) return null;
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('کجا پخش شود؟'),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: const Text('پلیر داخلی (پیشنهادی)'),
              onTap: () => Navigator.pop(context, 'internal'),
            ),
            ExpansionTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('پلیرهای خارجی'),
              children: [
                for (final player in ExternalVideoPlayer.values)
                  if (Platform.isAndroid || player == ExternalVideoPlayer.vlc)
                    ListTile(
                      title: Text(ExternalApps.playerName(player)),
                      onTap: () => Navigator.pop(context, player.name),
                    ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return choice;
  final label = choice == PlaybackPreferenceStore.internalPlayer
      ? 'پلیر داخلی'
      : ExternalApps.playerName(ExternalVideoPlayer.values.byName(choice));
  await maybeSuggestDefaultPlayer(context, value: choice, label: label);
  return choice;
}
