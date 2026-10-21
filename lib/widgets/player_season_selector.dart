import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/episode_catalog.dart';
import '../services/device_performance.dart';

/// Keep the desktop season strip; phones use a single, bounded dropdown even
/// in landscape, where a width breakpoint would mistake them for a desktop.
class PlayerSeasonSelector extends StatelessWidget {
  const PlayerSeasonSelector({
    super.key,
    required this.seasons,
    required this.selectedIndex,
    required this.onChanged,
    this.wrapDesktop = false,
  });

  final List<EpisodeSeasonGroup> seasons;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool wrapDesktop;

  @override
  Widget build(BuildContext context) {
    final mobile =
        DevicePerformance.appleMobileWeb ||
        (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS));
    if (mobile) {
      return DropdownButtonFormField<int>(
        key: const Key('player-season-dropdown'),
        // Flutter 3.32 (release CI) uses value; newer SDKs deprecate it.
        // ignore: deprecated_member_use
        value: selectedIndex,
        isExpanded: true,
        menuMaxHeight: math.min(320, MediaQuery.sizeOf(context).height * .6),
        decoration: const InputDecoration(
          labelText: 'انتخاب فصل',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: [
          for (final (index, item) in seasons.indexed)
            DropdownMenuItem(
              value: index,
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (index) {
          if (index != null) onChanged(index);
        },
      );
    }
    final chips = [
      for (final (index, item) in seasons.indexed)
        ChoiceChip(
          key: Key('player-season-${item.id}'),
          label: Text(item.name),
          selected: index == selectedIndex,
          onSelected: (_) => onChanged(index),
        ),
    ];
    if (wrapDesktop) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips) ...[chip, const SizedBox(width: 8)],
        ],
      ),
    );
  }
}
