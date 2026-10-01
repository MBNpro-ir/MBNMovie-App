import 'package:flutter/widgets.dart';
import '../services/web_gateway.dart';

/// انتخاب ارائه‌دهنده تصویر برای نشانی اینترنتی.
/// پس از حذف بخش ویژه، همه تصاویر با [NetworkImage] چارچوب بارگذاری می‌شوند.
ImageProvider imageProviderForUrl(String url) => NetworkImage(WebGateway.image(url));
