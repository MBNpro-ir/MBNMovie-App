// Browser regression harness. Build with --target=tools/ui_scale_probe.dart.
// Coordinates are read from Flutter's painted render boxes; tests send real
// browser touches at those coordinates without semantic click shortcuts.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:mbnmovie/app.dart';
import 'package:mbnmovie/core/episode_catalog.dart';
import 'package:mbnmovie/services/accessibility_service.dart';
import 'package:mbnmovie/services/browser_features.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/widgets/player_season_selector.dart';

final targets = <String, GlobalKey>{
  for (final name in [
    'viewport',
    'safe-content',
    'top',
    'middle',
    'bottom',
    'input',
    'dropdown',
    'modal',
  ])
    name: GlobalKey(),
};
final taps = <String>[];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DevicePerformance.configureWeb();
  globalContext.setProperty(
    'mbnProbeScale'.toJS,
    ((JSNumber scale) {
      AccessibilityService.instance.setUiScale(scale.toDartDouble);
    }).toJS,
  );
  globalContext.setProperty(
    'mbnProbeState'.toJS,
    (() {
      final boxes = <String, Object>{};
      for (final entry in targets.entries) {
        final box =
            entry.value.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final origin = box.localToGlobal(Offset.zero);
        final end = box.localToGlobal(box.size.bottomRight(Offset.zero));
        boxes[entry.key] = {
          'x': origin.dx,
          'y': origin.dy,
          'width': end.dx - origin.dx,
          'height': end.dy - origin.dy,
        };
      }
      return jsonEncode({
        'boxes': boxes,
        'taps': taps,
        'scale': AccessibilityService.instance.uiScale,
        'safeArea': {
          'left': BrowserFeatures.safeArea.left,
          'top': BrowserFeatures.safeArea.top,
          'right': BrowserFeatures.safeArea.right,
          'bottom': BrowserFeatures.safeArea.bottom,
        },
      }).toJS;
    }).toJS,
  );
  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (_, child) => AccessibilityAppWrapper(child: child!),
      home: const _Probe(),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int season = 0;
  Widget button(String name) => ElevatedButton(
    key: targets[name],
    onPressed: () {
      taps.add(name);
      if (name == 'middle') {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: TextButton(
              key: targets['modal'],
              onPressed: () {
                taps.add('modal');
                Navigator.pop(context);
              },
              child: const Text('close modal'),
            ),
          ),
        );
      }
    },
    child: Text(name),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    key: targets['viewport'],
    body: SafeArea(
      child: Stack(
        key: targets['safe-content'],
        children: [
          Positioned.fill(
            child: HtmlElementView.fromTagName(
              tagName: 'div',
              onElementCreated: (element) =>
                  (element as web.HTMLDivElement).style.pointerEvents = 'none',
            ),
          ),
          Column(
            children: [
              button('top'),
              TextField(
                key: targets['input'],
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
              ),
              PlayerSeasonSelector(
                key: targets['dropdown'],
                selectedIndex: season,
                seasons: [
                  for (var i = 0; i < 3; i++)
                    EpisodeSeasonGroup(
                      id: '$i',
                      name: 'Season ${i + 1}',
                      episodes: const [],
                    ),
                ],
                onChanged: (value) {
                  setState(() => season = value);
                  taps.add('season$value');
                },
              ),
              const Spacer(),
              button('middle'),
              const Spacer(),
              button('bottom'),
            ],
          ),
        ],
      ),
    ),
  );
}
