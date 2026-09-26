import 'package:flutter/widgets.dart';

/// Follow the first letter the user typed, while keeping Persian hints RTL.
TextDirection searchTextDirection(String value) {
  final latin = RegExp(r'[A-Za-z]').firstMatch(value)?.start;
  final persian = RegExp(r'[\u0600-\u06FF]').firstMatch(value)?.start;
  if (latin != null && (persian == null || latin < persian)) {
    return TextDirection.ltr;
  }
  return TextDirection.rtl;
}
