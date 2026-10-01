// How the video player's buttons look (Settings › Appearance › Video player, 0.1.40).
//
// The buttons sit straight on top of the picture, so a dark scene can swallow dark
// buttons and a bright one (snow, a white title card) can swallow white ones. The
// backing puts a soft halo or a disc behind every control in the opposite shade to
// the buttons, so they stand out over any picture.

import 'package:flutter/material.dart';

/// Button (and time text) size.
enum VideoButtonSize {
  small('Small', 22, 20),
  normal('Normal', 28, 24),
  large('Large', 36, 32);

  const VideoButtonSize(this.label, this.desktop, this.phone);
  final String label;

  /// Icon size on computers and on phones.
  final double desktop, phone;

  static VideoButtonSize? byName(Object? name) => values.where((v) => v.name == name).firstOrNull;
}

/// What goes behind each button so it can be seen over the picture.
enum VideoButtonBacking {
  none('None'),
  glow('Soft glow'),
  circle('Circles');

  const VideoButtonBacking(this.label);
  final String label;

  static VideoButtonBacking? byName(Object? name) => values.where((v) => v.name == name).firstOrNull;
}

/// A colour choice: 'white', 'black', 'accent' (the app theme's), or '#RRGGBB'.
Color resolveLookColour(String choice, Color accent, {Color fallback = Colors.white}) {
  switch (choice) {
    case 'white':
      return Colors.white;
    case 'black':
      return Colors.black;
    case 'red':
      return const Color(0xFFFF0000);
    case 'accent':
      return accent;
  }
  final hex = choice.startsWith('#') ? choice.substring(1) : choice;
  final v = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Is a colour light (so its backing should be dark)?
bool isLightColour(Color c) => c.computeLuminance() > 0.4;

/// Everything about the buttons' look, worked out into actual colours and sizes.
class VideoPlayerLook {
  const VideoPlayerLook({
    this.buttonColour = 'white',
    this.size = VideoButtonSize.normal,
    this.backing = VideoButtonBacking.glow,
    this.backingStrength = 0.55,
    this.seekColour = 'accent',
  });

  /// See [resolveLookColour].
  final String buttonColour;
  final VideoButtonSize size;
  final VideoButtonBacking backing;

  /// How solid the backing is, 0.2 to 0.9.
  final double backingStrength;

  /// The played part of the seek bar and its knob.
  final String seekColour;

  static const standard = VideoPlayerLook();

  Color buttons(Color accent) => resolveLookColour(buttonColour, accent);
  Color seek(Color accent) => resolveLookColour(seekColour, accent, fallback: accent);

  /// The shade behind the buttons: dark behind light buttons, light behind dark ones.
  Color backingColour(Color accent) {
    final base = isLightColour(buttons(accent)) ? Colors.black : Colors.white;
    return base.withValues(alpha: backingStrength.clamp(0.0, 1.0));
  }

  /// The unplayed part of the seek bar: the buttons' colour, faded, so it matches them.
  Color seekTrack(Color accent) => buttons(accent).withValues(alpha: 0.35);

  VideoPlayerLook copyWith({
    String? buttonColour,
    VideoButtonSize? size,
    VideoButtonBacking? backing,
    double? backingStrength,
    String? seekColour,
  }) => VideoPlayerLook(
    buttonColour: buttonColour ?? this.buttonColour,
    size: size ?? this.size,
    backing: backing ?? this.backing,
    backingStrength: backingStrength ?? this.backingStrength,
    seekColour: seekColour ?? this.seekColour,
  );

  Map<String, Object?> toJson() => {
    'buttonColour': buttonColour,
    'size': size.name,
    'backing': backing.name,
    'backingStrength': backingStrength,
    'seekColour': seekColour,
  };

  static String _colour(Object? v, String fallback) =>
      v is String && (const ['white', 'black', 'red', 'accent'].contains(v) || RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v))
      ? v
      : fallback;

  factory VideoPlayerLook.fromJson(Object? raw) {
    if (raw is! Map) return standard;
    final strength = raw['backingStrength'];
    return VideoPlayerLook(
      buttonColour: _colour(raw['buttonColour'], 'white'),
      size: VideoButtonSize.byName(raw['size']) ?? VideoButtonSize.normal,
      backing: VideoButtonBacking.byName(raw['backing']) ?? VideoButtonBacking.glow,
      backingStrength: strength is num ? strength.toDouble().clamp(0.2, 0.9) : 0.55,
      seekColour: _colour(raw['seekColour'], 'accent'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerLook &&
      other.buttonColour == buttonColour &&
      other.size == size &&
      other.backing == backing &&
      other.backingStrength == backingStrength &&
      other.seekColour == seekColour;

  @override
  int get hashCode => Object.hash(buttonColour, size, backing, backingStrength, seekColour);
}
