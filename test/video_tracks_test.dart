// Tests for audio and subtitle choices (0.1.40): picking the remembered track for a collection
// on the next episode, and how tracks are named in the Audio and subtitles window. The tracks
// are the ones the real engine reported for files in the user's library (tool/bench probes).
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/ui/screens/video_player_screen.dart' show matchTrack, trackLabel, languageName;
import 'package:media_kit/media_kit.dart';

void main() {
  // Toradora!: Japanese and English audio; full subtitles and signs & songs, both English.
  final audio = [
    AudioTrack.auto(),
    AudioTrack.no(),
    const AudioTrack('1', null, 'jpn', codec: 'opus', channels: 'unknown2'),
    const AudioTrack('2', null, 'eng', codec: 'opus', channels: 'unknown2'),
  ];
  final subs = [
    SubtitleTrack.auto(),
    SubtitleTrack.no(),
    const SubtitleTrack('1', 'Full Subtitles [MK-Baal]', 'eng', codec: 'ass'),
    const SubtitleTrack('2', 'Signs/Songs', 'eng', codec: 'ass'),
  ];

  test('the remembered language is picked on the next episode', () {
    expect(matchTrack(audio, const TrackPick(language: 'jpn'))!.id, '1');
    expect(matchTrack(audio, const TrackPick(language: 'eng'))!.id, '2');
    expect(matchTrack(audio, const TrackPick(language: 'fre')), isNull); // not there: keep the default
  });

  test('with two subtitles in one language, the same name wins', () {
    expect(matchTrack(subs, const TrackPick(language: 'eng', title: 'Signs/Songs'))!.id, '2');
    expect(matchTrack(subs, const TrackPick(language: 'eng', title: 'Something else'))!.id, '1');
    // A subtitle file added by name only.
    final withFile = [...subs, const SubtitleTrack('3', 'English (file)', 'eng', codec: 'subrip')];
    expect(matchTrack(withFile, const TrackPick(language: 'eng', title: 'English (file)'))!.id, '3');
  });

  test('track names in the window', () {
    expect(trackLabel('audio', audio[3], 2), 'English · Stereo · OPUS');
    expect(trackLabel('audio', const AudioTrack('1', null, 'eng', codec: 'ac3', channels: 'unknown6'), 1), 'English · 5.1 · AC3');
    expect(trackLabel('subtitles', subs[2], 1), 'Full Subtitles [MK-Baal] · English · ASS');
    expect(trackLabel('subtitles', const SubtitleTrack('1', 'SDH', 'eng', codec: 'subrip'), 1), 'SDH · English · SUBRIP');
    expect(trackLabel('audio', const AudioTrack('4', null, null), 4), 'Audio 4');
    expect(languageName('jpn'), 'Japanese');
    expect(languageName('xyz'), isNull);
  });
}
