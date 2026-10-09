// Audio and subtitle tracks in a video, in plain words (refactor phase 5, 9 Oct 2026; moved
// unchanged from video_player_screen.dart, which still exports them): language names, the label
// each track gets in the Audio and subtitles chooser, and finding the track that matches the
// choice remembered for a collection. No Flutter: tracks are read through `dynamic`, so these work
// with media_kit's AudioTrack / SubtitleTrack and with the engine layer's MediaTrack alike.
import '../models/video_item.dart' show TrackPick;

/// Language codes the engine reports, as words.
const _languages = {
  'eng': 'English', 'en': 'English', 'jpn': 'Japanese', 'ja': 'Japanese', 'spa': 'Spanish', 'es': 'Spanish',
  'fre': 'French', 'fra': 'French', 'fr': 'French', 'ger': 'German', 'deu': 'German', 'de': 'German',
  'ita': 'Italian', 'it': 'Italian', 'por': 'Portuguese', 'pt': 'Portuguese', 'rus': 'Russian', 'ru': 'Russian',
  'chi': 'Chinese', 'zho': 'Chinese', 'zh': 'Chinese', 'kor': 'Korean', 'ko': 'Korean', 'ara': 'Arabic',
  'hin': 'Hindi', 'dut': 'Dutch', 'nld': 'Dutch', 'swe': 'Swedish', 'nor': 'Norwegian', 'dan': 'Danish',
  'fin': 'Finnish', 'pol': 'Polish', 'tur': 'Turkish', 'gre': 'Greek', 'ell': 'Greek', 'heb': 'Hebrew',
  'tha': 'Thai', 'vie': 'Vietnamese', 'ind': 'Indonesian', 'hun': 'Hungarian', 'cze': 'Czech', 'ces': 'Czech',
};

String? languageName(String? code) => code == null ? null : _languages[code.toLowerCase()];

/// A language code for a subtitle file's label ("English" → "eng"), or null.
String? languageCodeFor(String label) {
  final l = label.toLowerCase();
  for (final e in _languages.entries) {
    if (e.key.length == 3 && l.contains(e.value.toLowerCase())) return e.key;
  }
  return null;
}

/// "English · 5.1 · AC3", "Full Subtitles [MK-Baal] · English".
String trackLabel(String kind, dynamic t, int n) {
  final String? title = t.title;
  final lang = languageName(t.language) ?? t.language;
  final parts = <String>[
    ?title,
    if (lang != null && lang != title) lang,
  ];
  if (kind == 'audio') {
    final ch = (t.channels ?? '') as String;
    final channels = switch (ch) {
      'unknown2' || 'stereo' => 'Stereo',
      'unknown1' || 'mono' => 'Mono',
      'unknown6' || '5.1' || '5.1(side)' => '5.1',
      'unknown8' || '7.1' => '7.1',
      _ => ch.isEmpty ? null : ch,
    };
    if (channels != null) parts.add(channels);
  }
  final String? codec = t.codec;
  if (codec != null) parts.add(codec.toUpperCase());
  if (parts.isEmpty) parts.add('${kind == 'audio' ? 'Audio' : 'Subtitles'} $n');
  return parts.join(' · ');
}

/// The audio or subtitle track in [tracks] that best matches [pick] (a choice remembered for the
/// collection): same language and name, else same language, else same name. Null when none does
/// (the file's own default is kept).
T? matchTrack<T>(List<T> tracks, TrackPick pick) {
  final real = [for (final t in tracks) if ((t as dynamic).id != 'auto' && (t as dynamic).id != 'no') t];
  for (final t in real) {
    final d = t as dynamic;
    if (d.language == pick.language && d.title == pick.title) return t;
  }
  for (final t in real) {
    if ((t as dynamic).language == pick.language && pick.language != null) return t;
  }
  for (final t in real) {
    if ((t as dynamic).title == pick.title && pick.title != null) return t;
  }
  return null;
}
