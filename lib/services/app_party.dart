import 'package:flutter/material.dart';
import 'package:mbn_party/mbn_party.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie_content.dart';
import '../core/episode_catalog.dart';
import '../screens/detail_screen.dart';
import 'movie_api.dart';

/// Only public catalog identity crosses the account service. Each device
/// resolves its own authorized stream and preferred quality.
class AppParty {
  static ContentApi? api;
  static void bind(ContentApi value) {
    api = value;
    PartyHub.instance.openMedia = open;
  }

  static PartyJson metadata(MovieContent item, EpisodeGroup group) => {
    'content_id': item.id,
    'episode_id': group.id,
    'title': item.title,
    'episode_title': group.name,
    'kind': item.kind.name,
    'poster': item.imageUrl ?? '',
    'source': 'movie',
  };

  static Future<void> send(BuildContext context, MovieContent item) async {
    final groups = EpisodeCatalog.from(
      item,
    ).episodes.where((g) => !g.isTrailer).toList();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('قسمت قابل پخشی پیدا نشد.')));
      return;
    }
    EpisodeGroup? group = groups.first;
    if (groups.length > 1) {
      group = await showDialog<EpisodeGroup>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('کدام قسمت را می‌فرستی؟'),
          children: [
            SizedBox(
              width: 420,
              height: 360,
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, groups[i]),
                  child: Text(groups[i].name),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
          ],
        ),
      );
    }
    if (group != null && context.mounted) {
      await sendPartyMedia(context, metadata(item, group));
    }
  }

  static Future<void> open(
    BuildContext context,
    PartyJson media,
    String? sessionId,
  ) async {
    final source = api;
    if (source == null) {
      throw const PartyException('کاتالوگ هنوز آماده نشده است.');
    }

    final summary = MovieContent(
      id: media['content_id'].toString(),
      title: media['title']?.toString() ?? '',
      subtitle: '',
      description: '',
      year: 0,
      rating: 0,
      kind: media['kind'] == 'series' ? ContentKind.series : ContentKind.movie,
      colors: const [Color(0xFF172235), Color(0xFF0D1422)],
      genres: const [],
    );
    final item = await source.details(summary);
    if (!context.mounted) return;
    final catalog = EpisodeCatalog.from(item),
        id = media['episode_id']?.toString() ?? '';
    final group = catalog.episodes
        .where((g) => g.id == id || g.variants.any((v) => v.episode.id == id))
        .firstOrNull;
    // Never silently join another episode if a source changed its catalog.
    if (group == null) {
      throw const PartyException(
        'این قسمت در کاتالوگ فعلی پیدا نشد؛ دعوت تازه‌ای ارسال کن.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final variant = group.variantFor(
      prefs.getString('preferred_stream_quality'),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    await navigator.pushAndRemoveUntil<void>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          content: item,
          episode: variant.episode,
          partySessionId: sessionId,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}
