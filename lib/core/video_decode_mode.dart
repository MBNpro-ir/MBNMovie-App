/// Account-synced preference; native output policy remains device specific.
enum VideoDecodeMode {
  hardware,
  software;

  static const preferenceKey = 'player_decoder_mode';

  static VideoDecodeMode parse(Object? value) =>
      value == 'software' ? software : hardware;

  static bool isValid(Object? value) =>
      value == 'hardware' || value == 'software';
}
