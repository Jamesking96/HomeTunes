// Tests for reading video folders and file names (0.1.32, services/video_names.dart): categories,
// collection names tidied of release details, seasons from folders, episodes and titles from
// file names, specials and extras. The names are real ones from the user's video library.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/video_names.dart';
import 'package:path/path.dart' as p;

void main() {
  const root = r'F:\Videos';
  VideoPathInfo d(String rel) => describeVideoPath(root, p.join(root, rel));

  group('collection names', () {
    test('release details, brackets and years come off', () {
      expect(cleanVideoName('Battlestar Galactica (2003) Season 1-4 S01-S04 (1080p BluRay x265 HEVC 10bit AAC 5.1 RZeroX)'),
          (title: 'Battlestar Galactica', year: 2003));
      expect(cleanVideoName('South Park - Complete'), (title: 'South Park', year: null));
      expect(cleanVideoName('Ghosts US - S1-2'), (title: 'Ghosts US', year: null));
      expect(cleanVideoName('Claymore 1-26 DVDRip (Dual Audio)'), (title: 'Claymore', year: null));
      expect(cleanVideoName('Black Rock Shooter Complete Collection_(BD720p_10bit_HEVC_SmoodFlamez)').title, 'Black Rock Shooter');
      expect(cleanVideoName('Death Note (TV Series 2006-2007)'), (title: 'Death Note', year: 2006));
      expect(cleanVideoName('Delicious in Dungeon [BD][1080p][HEVC 10bit x265][Dual Audio][Tenrai-Sensei]').title,
          'Delicious in Dungeon');
      expect(cleanVideoName('Avatar - The Last Airbender (2005 - 2008) [1080p]'), (title: 'Avatar - The Last Airbender', year: 2005));
      expect(cleanVideoName('Toradora! v2 [1080p BD AV1][dual audio]').title, 'Toradora!');
      expect(cleanVideoName('[DeadFish] Steins;Gate - Batch [BD][720p][MP4][AAC]').title, 'Steins;Gate');
    });

    test('films: dotted names and a year before the release details', () {
      expect(cleanVideoName('Mickey.17.2025.2160p.HDR10Plus.DV.WEBRip.DDP5 1.Atmos.X265.HEVC-PSA'), (title: 'Mickey 17', year: 2025));
      expect(cleanVideoName('The Naked Gun 2025 1080p WEB-DL HEVC x265 5.1 BONE'), (title: 'The Naked Gun', year: 2025));
      expect(cleanVideoName('Avatar.The.Legend.of.Aang.The.Last.Airbender.2026.1080p.PMNTP.WEBRip.AAC2.0.H264-[LEAK]'),
          (title: 'Avatar The Legend of Aang The Last Airbender', year: 2026));
      expect(cleanVideoName('Blade Runner 2049 (2017)'), (title: 'Blade Runner 2049', year: 2017));
      expect(cleanVideoName('Blade Runner 2049').title, 'Blade Runner 2049');
    });
  });

  group('where a video sits', () {
    test('TV: category, collection, season folder, episode and title', () {
      final v = d(r'TV\South Park - Complete\Season 02\South Park (1997) - S02E11 - Roger Ebert Should Lay Off the Fatty Foods '
          r'[WEBDL-1080p][AC3 5.1][h264]-CtrlHD.mkv');
      expect(v.category, 'TV');
      expect(v.collection, 'South Park');
      expect(v.collectionFolder, p.join(root, 'TV', 'South Park - Complete'));
      expect((v.season, v.episode), (2, 11));
      expect(v.title, 'Roger Ebert Should Lay Off the Fatty Foods');
    });

    test('episodes named only by release details are "Episode n"', () {
      final v = d(r'TV\Samurai Jack - Complete\Samurai.Jack.S02.1080p.BluRay.x264-pcroland[rartv]\Samurai.Jack.S02E11.1080p.BluRay.DD2.0.x264-pcroland.mkv');
      expect((v.collection, v.season, v.episode, v.title), ('Samurai Jack', 2, 11, 'Episode 11'));
      final u = d(r'TV\Ugly Americans - Complete\Ugly.Americans.S02.1080p.WEB-DL.AAC2.0.H264-NOGRP[rartv]\Ugly.Americans.S02E14.Mark.Loves.Dick.1080p.WEB-DL.AAC2.0.H.264.mkv');
      expect((u.season, u.episode, u.title), (2, 14, 'Mark Loves Dick'));
    });

    test('other episode styles', () {
      expect(d(r'Anime\Claymore 1-26 DVDRip (Dual Audio)\Claymore Ep. 11 - Those Who Rend Asunder III.mkv').episode, 11);
      expect(d(r'Anime\Claymore 1-26 DVDRip (Dual Audio)\Claymore Ep. 11 - Those Who Rend Asunder III.mkv').title,
          'Those Who Rend Asunder III');
      final dn = d(r'Anime\Death Note (TV Series 2006-2007)\Episode 21 Performance.mkv');
      expect((dn.episode, dn.title), (21, 'Performance'));
      final dtb = d(r'Anime\DARKER Than BLACK (2007-2010) - Complete Series, OVAs, OSTs - 720p DUAL Audio x264\1c. Season 2 (2009)\DARKER Than BLACK - S02 E02 - Fallen Meteor (720p - DUAL Audio).mkv');
      expect((dtb.collection, dtb.season, dtb.episode, dtb.title), ('DARKER Than BLACK', 2, 2, 'Fallen Meteor'));
      final ted = d(r'TV\Ted - S1-2\Ted S02 720p - PW\Ted (2024) Season 2 Episode 7- Susan Is the New Black - PrimeWire.mp4');
      expect((ted.season, ted.episode, ted.title), (2, 7, 'Susan Is the New Black'));
      final tora = d(r'Anime\Toradora! v2 [1080p BD AV1][dual audio]\[Sokudo] Toradora! - 03 v2 [1080p BD AV1][dual audio].mkv');
      expect((tora.collection, tora.episode, tora.title), ('Toradora!', 3, 'Episode 3'));
      expect(d(r'Anime\Fullmetal ALchemist BrotherHood[720p] [Dual-Audio][eng subbed]{Neroextreme}_NTRG\Fullmetal Alchemist BrotherHood 16.mkv').episode, 16);
      expect(d(r'TV\Silo - S1-3\Silo Season 1 Mp4 1080p\Silo S01E08.mp4').season, 1);
    });

    test('seasons from folders: "Book Two", "S03", and Specials as season 0', () {
      final korra = d(r'TV\The Legend of Korra (2012 - 2014) [1080p]\Book 3 - Change\The Legend of Korra - S03E08 - The Terror Within.mkv');
      expect((korra.season, korra.title), (3, 'The Terror Within'));
      expect(seasonOfFolder('Book Two - Earth'), 2);
      expect(seasonOfFolder('S03'), 3);
      expect(seasonOfFolder('Season 01'), 1);
      expect(seasonOfFolder('2b. Specials (2011-12)'), 0);
      expect(seasonOfFolder('Ghosts.2021.S01.1080p.BluRay.x265[eztv.re]'), 1);
      expect(seasonOfFolder('Featurettes'), isNull);
      final special = d(r'TV\Battlestar Galactica (2003) Season 1-4 S01-S04 (1080p BluRay x265 HEVC 10bit AAC 5.1 RZeroX)\Specials\Battlestar Galactica (2003) - S00E22 - The Plan (1080p x265 RZeroX).mkv');
      expect((special.season, special.episode, special.title), (0, 22, 'The Plan'));
    });

    test('extras folders', () {
      final bts = d(r'TV\Battlestar Galactica (2003) Season 1-4 S01-S04 (1080p BluRay x265 HEVC 10bit AAC 5.1 RZeroX)\Featurettes\Season 1\Season 1 - Deleted Scenes #3.mkv');
      expect(bts.extra, isTrue);
      expect(bts.season, isNull);
      expect(d(r'Anime\Black Lagoon\NCOP and NCED\[Anime Time] Black Lagoon ED 01  - Don''t Look Behind.mkv').extra, isTrue);
      expect(d(r'Anime\Kiss X Sis (Season 1 + OVAs) (BD 1080p)(HEVC x265 10bit)(Eng-Subs)-Judas[TGx]\[Judas] Kiss X Sis S1\Extras\[Judas] Kiss X Sis - NCED01a.mkv').extra, isTrue);
    });

    test('named parts without season numbers, the collection name taken off', () {
      final sao = d(r'Anime\Sword Art Online - Collection\[Anime Time] Sword Art Online - Alicization\[Anime Time] Sword Art Online - Alicization - 14.mkv');
      expect((sao.collection, sao.part, sao.episode), ('Sword Art Online', 'Alicization', 14));
      final champloo = d(r'Anime\Samurai Champloo Complete Series [1-26] [720p Dual Audio] L@mBerT\Samurai Champloo\Samurai Champloo - 06 L@mBerT.mkv');
      expect((champloo.collection, champloo.part, champloo.episode), ('Samurai Champloo', null, 6));
    });

    test('films: each its own collection, never an "episode"', () {
      final loose = d(r'Films\The Naked Gun 2025 1080p WEB-DL HEVC x265 5.1 BONE.mkv');
      expect((loose.category, loose.collection, loose.year, loose.episode), ('Films', 'The Naked Gun', 2025, null));
      final inFolder = d(r'Films\Mickey.17.2025.2160p.HDR10Plus.DV.WEBRip.DDP5 1.Atmos.X265.HEVC-PSA\Mickey.17.2025.2160p.HDR10Plus.DV.WEBRip.DDP5 1.Atmos.X265.HEVC-PSA.mkv');
      expect((inFolder.collection, inFolder.year, inFolder.episode, inFolder.title), ('Mickey 17', 2025, null, 'Mickey 17'));
    });

    test('no category folder: the first folder is the collection; loose files share the video folder\'s name', () {
      expect(describeVideoPath(r'D:\Home videos', r'D:\Home videos\Holiday 2024\Beach.mp4').collection, 'Holiday 2024');
      expect(describeVideoPath(r'D:\My clips', r'D:\My clips\cat.mp4').collection, 'My clips');
      // A video folder that is itself a category.
      final tv = describeVideoPath(r'F:\Videos\TV', r'F:\Videos\TV\Silo - S1-3\Silo Season 1 Mp4 1080p\Silo S01E08.mp4');
      expect((tv.category, tv.collection), ('TV', 'Silo'));
    });
  });

  test('subtitle file labels', () {
    expect(subtitleLabel(r'X:\Subs\Ghosts.2021.S01E01\3_English.srt', r'X:\Ghosts.2021.S01E01.mp4'), 'English');
    expect(subtitleLabel(r'X:\Film.en.forced.srt', r'X:\Film.mkv'), 'en forced');
    expect(subtitleLabel(r'X:\Film.srt', r'X:\Film.mkv'), 'External');
  });
}
