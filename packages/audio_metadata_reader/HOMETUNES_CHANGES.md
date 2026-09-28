# HomeTunes changes to audio_metadata_reader 1.8.0

A local copy of [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)
1.8.0 (MIT, see LICENSE), used by HomeTunes via a path dependency.

Why: when "Save edits into files" rewrote a file's tags, the 1.8.0 writers
kept only the fields they know about. Everything else in the file was
thrown away:
- MP3: lyrics (USLT), ReplayGain and other TXXX frames, comments and chapters.
- FLAC: lyrics, disc number, ReplayGain, composer and other comments.
- MP4/M4A: album artist, ReplayGain ("----" items), composer and similar items.

Changes (each is marked `HomeTunes:` in the code):
- `lib/src/writers/id3v4_writer.dart`: writes lyrics as a USLT frame. Carries over
  every ID3v2.3/2.4 frame the writer doesn't manage (`keptId3v2Frames`).
- `lib/src/writers/flac_writer.dart`: writes DISCNUMBER and LYRICS. Carries over
  comments the writer doesn't manage (`keptVorbisComments`).
- `lib/src/writers/mp4_writer.dart`: carries over ilst items the writer didn't write.
- `lib/src/parsers/tags/id3v2.dart`: reads Latin-1/UTF-8 USLT lyrics correctly
  when the frame has a description. Before, the first character was lost.
- `lib/src/utils/buffer.dart` (HomeTunes 0.1.21, security review #7): `read(size)` throws a
  `MetadataParserException` instead of allocating when a block claims more than 1 MB past the
  end of the file. A crafted MP3 or M4A could otherwise ask for a multi-gigabyte list during a
  scan. Reads that fit in the 16 KB buffer aren't checked, so scanning isn't slowed down.
