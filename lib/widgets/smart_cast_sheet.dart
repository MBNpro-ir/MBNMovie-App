import 'dart:async';

import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/movie_content.dart';
import 'default_preference_prompt.dart';

enum TvDestination { googleCast, dlna, lgWebOs, airPlay, fireTv, rokuXbox }

extension TvDestinationInfo on TvDestination {
  String get title => switch (this) {
    TvDestination.googleCast => 'Chromecast و Google TV',
    TvDestination.dlna => 'تلویزیون DLNA',
    TvDestination.lgWebOs => 'LG webOS',
    TvDestination.airPlay => 'Apple TV و AirPlay (آزمایشی)',
    TvDestination.fireTv => 'Amazon Fire TV',
    TvDestination.rokuXbox => 'Roku یا Xbox',
  };

  String get description => switch (this) {
    TvDestination.googleCast => 'Android TV و تلویزیون دارای Google Cast',
    TvDestination.dlna => 'Samsung، Sony، Hisense و گیرنده‌های UPnP/DLNA',
    TvDestination.lgWebOs => 'اشتراک‌گذاری DLNA تلویزیون باید روشن باشد',
    TvDestination.airPlay =>
      'نیازمند AirPlay Video؛ سازگاری به مدل و نرم‌افزار گیرنده بستگی دارد',
    TvDestination.fireTv => 'برنامه گیرنده DLNA/Cast روی Fire TV لازم است',
    TvDestination.rokuXbox => 'Media Player یا گیرنده DLNA باید فعال باشد',
  };

  IconData get icon => switch (this) {
    TvDestination.googleCast => Icons.cast_rounded,
    TvDestination.airPlay => Icons.airplay_rounded,
    TvDestination.fireTv => Icons.local_fire_department_rounded,
    TvDestination.rokuXbox => Icons.sports_esports_rounded,
    _ => Icons.tv_rounded,
  };

  CastProtocol get protocol => switch (this) {
    TvDestination.googleCast => CastProtocol.chromecast,
    TvDestination.airPlay => CastProtocol.airplay,
    _ => CastProtocol.dlna,
  };
}

Future<bool?> showSmartCastSheet(
  BuildContext context, {
  required MovieContent content,
  required MovieEpisode episode,
  String? initialDestination,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: MovieColors.surface,
  builder: (_) => _SmartCastSheet(
    content: content,
    episode: episode,
    initialDestination: initialDestination,
  ),
);

class SmartCastController {
  SmartCastController._()
    : _service = CastService(
        discoveryProviders: [
          ChromecastDiscoveryProvider(),
          DlnaDiscoveryProvider(),
          AirPlayDiscoveryProvider(),
        ],
      );

  static final instance = SmartCastController._();
  final CastService _service;
  CastSession? _session;
  // Serializes overlapping cast attempts: only the newest generation may
  // publish ownership. Superseded/failing candidates are always closed so
  // two concurrent sessions can never both load media with the loser left
  // unowned, and a dismissed sheet's late connection never overwrites a
  // newer one (it is closed instead).
  int _castGeneration = 0;

  Stream<List<CastDevice>> discover(CastProtocol protocol) =>
      _service.startDiscovery(
        protocols: {protocol},
        timeout: const Duration(seconds: 12),
      );

  void stopDiscovery() => _service.stopDiscovery();

  Future<void> cast({
    required CastDevice device,
    required MovieContent content,
    required MovieEpisode episode,
  }) async {
    final generation = ++_castGeneration;
    final previous = _session;
    _session = null;
    if (previous != null) {
      try {
        await previous.disconnect();
      } catch (_) {}
    }
    if (generation != _castGeneration) return;
    final CastSession candidate = switch (device.protocol) {
      CastProtocol.chromecast => ChromecastSession(device: device),
      CastProtocol.dlna => DlnaSession.fromDevice(device),
      CastProtocol.airplay => AirPlaySession(device),
    };
    try {
      await candidate.connect();
    } catch (e) {
      try {
        await candidate.disconnect();
      } catch (_) {}
      if (generation == _castGeneration) rethrow;
      return;
    }
    if (generation != _castGeneration) {
      try {
        await candidate.disconnect();
      } catch (_) {}
      return;
    }
    _session = candidate;
    try {
      await candidate.loadMedia(
        CastMedia(
          url: episode.fileUrl,
          type: _mediaType(episode.fileUrl, episode.fileType),
          title: '${content.title} · ${episode.name}',
          imageUrl: content.imageUrl,
        ),
      );
    } catch (e) {
      if (_session == candidate) _session = null;
      try {
        await candidate.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _castGeneration++;
    final current = _session;
    _session = null;
    if (current != null) {
      try {
        await current.disconnect();
      } catch (_) {}
    }
  }

  static CastMediaType _mediaType(String url, String fileType) {
    final value = '$url $fileType'.toLowerCase();
    if (value.contains('.m3u8') || value.contains('hls')) {
      return CastMediaType.hls;
    }
    if (value.contains('.mkv')) return CastMediaType.mkv;
    if (value.contains('.ts')) return CastMediaType.mpegTs;
    return CastMediaType.mp4;
  }
}

class _SmartCastSheet extends StatefulWidget {
  const _SmartCastSheet({
    required this.content,
    required this.episode,
    this.initialDestination,
  });
  final MovieContent content;
  final MovieEpisode episode;
  final String? initialDestination;

  @override
  State<_SmartCastSheet> createState() => _SmartCastSheetState();
}

class _SmartCastSheetState extends State<_SmartCastSheet> {
  final _devices = <CastDevice>[];
  StreamSubscription<List<CastDevice>>? _subscription;
  TvDestination? _destination;
  bool _scanning = false;
  String? _connectingId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDestination;
    if (initial != null) {
      for (final destination in TvDestination.values) {
        if (destination.name == initial) {
          _destination = destination;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
          break;
        }
      }
    }
  }

  Future<void> _selectDestination(TvDestination destination) async {
    setState(() => _destination = destination);
    await maybeSuggestDefaultStreamer(
      context,
      value: destination.name,
      label: destination.title,
    );
    if (!mounted) return;
    _scan();
  }

  void _scan() {
    final destination = _destination;
    if (destination == null) return;
    _subscription?.cancel();
    setState(() {
      _devices.clear();
      _scanning = true;
      _error = null;
    });
    _subscription = SmartCastController.instance
        .discover(destination.protocol)
        .listen(
          (devices) {
            if (!mounted) return;
            setState(() {
              _devices
                ..clear()
                ..addAll(devices);
            });
          },
          onDone: () {
            if (mounted) setState(() => _scanning = false);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _scanning = false;
              _error = error;
            });
          },
        );
  }

  void _changeDestination() {
    _subscription?.cancel();
    SmartCastController.instance.stopDiscovery();
    setState(() {
      _destination = null;
      _devices.clear();
      _scanning = false;
      _error = null;
    });
  }

  Future<void> _connect(CastDevice device) async {
    setState(() => _connectingId = device.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SmartCastController.instance.cast(
        device: device,
        content: widget.content,
        episode: widget.episode,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(content: Text('پخش روی ${device.name} شروع شد.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectingId = null;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    SmartCastController.instance.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .78,
    child: Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white38,
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        ListTile(
          leading: Icon(_destination?.icon ?? Icons.cast_connected_rounded),
          title: Text(_destination?.title ?? 'نوع تلویزیون را انتخاب کن'),
          subtitle: Text(
            _destination?.description ??
                '${widget.content.title} · ${widget.episode.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton.icon(
            onPressed: _destination == null
                ? () => Navigator.pop(context)
                : _changeDestination,
            icon: const BackButtonIcon(),
            label: const Text('بازگشت'),
          ),
        ),
        const Divider(height: 1),
        if (_destination == null)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 310,
                mainAxisExtent:
                    150 +
                    (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                          0,
                          60,
                        ) *
                        5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: TvDestination.values.length,
              itemBuilder: (context, index) {
                final destination = TvDestination.values[index];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _selectDestination(destination),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            destination.icon,
                            color: MovieColors.orange,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  destination.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  destination.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MovieColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else ...[
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'اتصال انجام نشد. مقصد و MBNMovie باید روی یک شبکه باشند.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MovieColors.muted),
              ),
            ),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _destination!.icon,
                            size: 54,
                            color: MovieColors.orange,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _scanning
                                ? 'در حال جست‌وجوی ${_destination!.title}…'
                                : 'دستگاهی پیدا نشد. گیرنده مربوط را روی تلویزیون روشن کن و دوباره جست‌وجو کن.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: MovieColors.muted),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _scanning ? null : _scan,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('جست‌وجوی دوباره'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final busy = _connectingId == device.id;
                      return Card(
                        child: ListTile(
                          onTap: _connectingId == null
                              ? () => _connect(device)
                              : null,
                          leading: Icon(
                            _destination!.icon,
                            color: MovieColors.orange,
                          ),
                          title: Text(device.name),
                          subtitle: Text(_destination!.title),
                          trailing: busy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chevron_left_rounded),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    ),
  );
}
