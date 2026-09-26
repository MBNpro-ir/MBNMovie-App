import 'package:flutter/material.dart';

import '../models/movie_content.dart';

const demoCatalog = <MovieContent>[
  MovieContent(
    id: 'skyward',
    title: 'آن‌سوی آسمان',
    subtitle: 'Skyward · فصل اول',
    description:
        'دختری جوان در شهری شناور، رازی را پیدا می‌کند که می‌تواند سرنوشت دو جهان را برای همیشه تغییر دهد.',
    year: 2026,
    rating: 8.9,
    kind: ContentKind.series,
    colors: [Color(0xFF512DA8), Color(0xFFFF6D55)],
    genres: ['ماجراجویی', 'فانتزی', 'درام'],
    episodes: 12,
    progress: .42,
  ),
  MovieContent(
    id: 'neon-district',
    title: 'منطقه نئون',
    subtitle: 'Neon District',
    description:
        'کارآگاهی تنها در دل شهری آینده‌نگر به دنبال حقیقتی می‌رود که حافظه‌اش را زیر سؤال می‌برد.',
    year: 2025,
    rating: 8.4,
    kind: ContentKind.series,
    colors: [Color(0xFF006064), Color(0xFF7C4DFF)],
    genres: ['علمی‌تخیلی', 'معمایی'],
    episodes: 8,
  ),
  MovieContent(
    id: 'red-moon',
    title: 'ماه سرخ',
    subtitle: 'Red Moon',
    description:
        'یک سامورایی جوان برای نجات روستایش باید با سایه‌هایی از گذشته روبه‌رو شود.',
    year: 2024,
    rating: 9.1,
    kind: ContentKind.movie,
    colors: [Color(0xFF4A0B16), Color(0xFFFF5722)],
    genres: ['اکشن', 'تاریخی'],
  ),
  MovieContent(
    id: 'quiet-sea',
    title: 'دریای خاموش',
    subtitle: 'The Quiet Sea',
    description:
        'دو دوست در یک جزیره دورافتاده، نشانه‌هایی از تمدنی فراموش‌شده را کشف می‌کنند.',
    year: 2026,
    rating: 7.9,
    kind: ContentKind.movie,
    colors: [Color(0xFF0D47A1), Color(0xFF26C6DA)],
    genres: ['درام', 'ماجراجویی'],
  ),
  MovieContent(
    id: 'paper-hearts',
    title: 'قلب‌های کاغذی',
    subtitle: 'Paper Hearts',
    description:
        'نامه‌ای که هرگز ارسال نشد، پس از ده سال دو زندگی را دوباره به هم پیوند می‌دهد.',
    year: 2025,
    rating: 8.2,
    kind: ContentKind.series,
    colors: [Color(0xFFAD1457), Color(0xFFFFB74D)],
    genres: ['عاشقانه', 'درام'],
    episodes: 10,
  ),
  MovieContent(
    id: 'last-orbit',
    title: 'آخرین مدار',
    subtitle: 'Last Orbit',
    description:
        'خدمه یک ایستگاه فضایی با آخرین فرصت خود برای بازگشت به خانه روبه‌رو می‌شوند.',
    year: 2023,
    rating: 8.6,
    kind: ContentKind.series,
    colors: [Color(0xFF102027), Color(0xFF455A64)],
    genres: ['علمی‌تخیلی', 'هیجان‌انگیز'],
    episodes: 16,
    progress: .68,
  ),
];
