import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class PlayerFileDropRegion extends StatefulWidget {
  const PlayerFileDropRegion({
    super.key,
    required this.enabled,
    required this.onFiles,
    required this.child,
  });
  final bool enabled;
  final Future<void> Function(List<String>) onFiles;
  final Widget child;
  @override
  State<PlayerFileDropRegion> createState() => _PlayerFileDropRegionState();
}

class _PlayerFileDropRegionState extends State<PlayerFileDropRegion> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => DropTarget(
    enable: widget.enabled,
    onDragEntered: (_) => setState(() => _hover = true),
    onDragExited: (_) => setState(() => _hover = false),
    onDragDone: (event) async {
      setState(() => _hover = false);
      if (widget.enabled) {
        await widget.onFiles(
          event.files.map((f) => f.path).toList(growable: false),
        );
      }
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_hover && widget.enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .62),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF172238),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF69DED2),
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.playlist_add_rounded,
                          size: 54,
                          color: Color(0xFF69DED2),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'فایل صدا یا زیرنویس را اینجا رها کن',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, color: Colors.white),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'برای همین ویدیو ذخیره و فعال می‌شود',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
