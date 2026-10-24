import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/screens/settings_screen.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/app.dart';
import 'package:mbnmovie/services/device_performance.dart';

@JS('mbnDecoderState')
external set probeState(JSString value);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DevicePerformance.configureWeb();
  final prefs = await SharedPreferences.getInstance();
  Map<String, double>? decoderRect() {
    RenderBox? found;
    void visit(Element element) {
      if (element.widget.key == const Key('player-decoder-mode')) {
        found = element.findRenderObject() as RenderBox?;
      }
      element.visitChildren(visit);
    }
    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final box = found;
    if (box == null || !box.attached || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return {'x': offset.dx, 'y': offset.dy, 'width': box.size.width, 'height': box.size.height};
  }
  void report() => probeState = jsonEncode({
    'mode': prefs.get('player_decoder_mode'),
    'rect': decoderRect(),
  }).toJS;
  report();
  Timer.periodic(const Duration(milliseconds: 150), (_) => report());
  runApp(MaterialApp(theme: MovieTheme.dark,
    builder: (_, child) => AccessibilityAppWrapper(child: child!),
    home: const Directionality(textDirection: TextDirection.rtl,
      child: SettingsScreen())));
}
