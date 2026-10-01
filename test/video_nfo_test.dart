// .nfo files (services/video_nfo.dart): reading Kodi / Jellyfin details, and writing HomeTunes'
// details into a file made by another program without losing anything else in it.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/video_nfo.dart';

void main() {
  const kodi = '''<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!-- made by Kodi -->
<episodedetails>
    <title>The Engineer</title>
    <showtitle>Silo</showtitle>
    <season>1</season>
    <episode>2</episode>
    <genre>Drama</genre>
    <genre>Sci-Fi</genre>
    <plot><![CDATA[Juliette <goes> down.]]></plot>
    <aired>2023-05-12</aired>
    <uniqueid type="tvdb" default="true">9559412</uniqueid>
    <actor>
        <name>Rebecca Ferguson</name>
    </actor>
</episodedetails>
''';

  test('reads the details HomeTunes uses', () {
    final n = parseNfo(kodi);
    expect((n.title, n.showTitle, n.season, n.episode, n.genre, n.year), ('The Engineer', 'Silo', 1, 2, 'Drama', 2023));
    expect(n.plot, 'Juliette <goes> down.');
    expect(parseNfo('<movie><title>Up &amp; Away</title><set><name>Pixar</name></set></movie>').set, 'Pixar');
    expect(parseNfo('<movie><set>Old style</set><year>1999</year></movie>'), isA<NfoInfo>().having((n) => n.set, 'set', 'Old style'));
  });

  test('writing replaces only its own tags and keeps the rest', () {
    final out = updateNfo(kodi, 'episodedetails',
        {'title': 'Machines', 'showtitle': 'Silo', 'season': '1', 'episode': '3', 'year': '2023', 'genre': 'Drama', 'plot': null});
    expect(out, contains('<!-- made by Kodi -->'));
    expect(out, contains('<uniqueid type="tvdb" default="true">9559412</uniqueid>'));
    expect(out, contains('<name>Rebecca Ferguson</name>'));
    expect(out, contains('<title>Machines</title>'));
    expect(out, contains('<episode>3</episode>'));
    expect(out, isNot(contains('<plot>'))); // emptied
    expect('<genre>'.allMatches(out).length, 1);
    expect(out, contains('<year>2023</year>'));
    final back = parseNfo(out);
    expect((back.title, back.episode, back.year, back.plot), ('Machines', 3, 2023, null));
    // Writing the same again changes nothing.
    expect(updateNfo(out, 'episodedetails',
        {'title': 'Machines', 'showtitle': 'Silo', 'season': '1', 'episode': '3', 'year': '2023', 'genre': 'Drama', 'plot': null}), out);
  });

  test('a new file, and a film that became an episode', () {
    final fresh = updateNfo(null, 'movie', {'title': 'Tom & Jerry', 'set': 'Cartoons', 'year': null});
    expect(fresh, startsWith('<?xml'));
    expect(parseNfo(fresh).title, 'Tom & Jerry');
    expect(parseNfo(fresh).set, 'Cartoons');
    final switched = updateNfo(fresh, 'episodedetails', {'showtitle': 'Cartoons', 'set': null, 'episode': '4'});
    expect(switched, allOf(contains('<episodedetails>'), contains('</episodedetails>'), isNot(contains('<movie')),
        isNot(contains('<set>'))));
    expect(parseNfo(switched).episode, 4);
  });
}
