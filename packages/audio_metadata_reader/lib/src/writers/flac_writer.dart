import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart';

typedef _Block = ({int type, Uint8List data});

/// Writer for FLAC metadata blocks (Vorbis comments and pictures).
class FlacWriter extends BaseMetadataWriter<VorbisMetadata> {
  /// Rebuilds FLAC metadata from [source] into [destination].
  ///
  /// The base writer owns the temporary file and calls this method with a
  /// read-only source, so this method only serializes the FLAC replacement.
  @override
  void writeContents(File source, File destination, VorbisMetadata metadata) {
    final reader = source.openSync();
    late final Uint8List output;

    try {
      reader.setPositionSync(0);
      final magic = reader.readSync(4);

      // Comment and picture blocks get regenerated, rest carries over
      final kept = <_Block>[];
      Uint8List? oldComments;
      var isLastBlock = false;

      while (!isLastBlock) {
        final header = reader.readSync(4);
        isLastBlock = header[0] >> 7 == 1;
        final type = header[0] & 0x7F;
        final length = header[3] | header[2] << 8 | header[1] << 16;

        if (type == 4) {
          oldComments ??= reader.readSync(length);
        } else if (type == 6) {
          reader.setPositionSync(reader.positionSync() + length);
        } else {
          kept.add((type: type, data: reader.readSync(length)));
        }
      }

      final audioStart = reader.positionSync();

      // Streaminfo needs to stay first
      final blocks = <_Block>[];
      if (kept.isNotEmpty && kept.first.type == 0) {
        blocks.add(kept.removeAt(0));
      }
      blocks.add((type: 4, data: _buildVorbisComments(metadata, oldComments)));
      for (final picture in metadata.pictures) {
        blocks.add((type: 6, data: _buildPictureBlock(picture)));
      }
      blocks.addAll(kept);

      final builder = BytesBuilder();
      builder.add(magic);

      // Flag real last block, otherwise the decoder reads into frames
      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        _writeBlockHeader(
          builder,
          block.type,
          block.data.length,
          i == blocks.length - 1,
        );
        builder.add(block.data);
      }

      reader.setPositionSync(audioStart);
      builder.add(reader.readSync(reader.lengthSync() - audioStart));

      output = builder.takeBytes();
    } finally {
      reader.closeSync();
    }

    destination.writeAsBytesSync(output);
  }

  void _writeBlockHeader(
      BytesBuilder builder, int blockType, int length, bool isLastBlock) {
    var firstByte = isLastBlock ? (1 << 7) : 0;
    firstByte = (firstByte | (blockType & 0x7F));

    builder.addByte(firstByte);
    builder.add(intToUint24(length));
  }

  Uint8List _buildPictureBlock(Picture picture) {
    final headerBytes = BytesBuilder();

    headerBytes.add(intToUint32(picture.pictureType.index));
    headerBytes.add(intToUint32(picture.mimetype.length));
    headerBytes.add(ascii.encode(picture.mimetype));
    headerBytes.add(intToUint32(0)); // No Description for now
    headerBytes.add(intToUint32(0)); // No width for now
    headerBytes.add(intToUint32(0)); // No height for now
    headerBytes.add(intToUint32(0)); // No color depth for now
    headerBytes.add(intToUint32(0)); // No color number for now
    headerBytes.add(intToUint32(picture.bytes.length));
    headerBytes.add(picture.bytes);

    return headerBytes.takeBytes();
  }

  Uint8List _buildVorbisComments(VorbisMetadata metadata, [Uint8List? old]) {
    final mainBuilder = BytesBuilder();
    final commentsBuilder = BytesBuilder();

    // vendor length
    // I don't know what to use. The library name? The user selects the name he wants?
    mainBuilder.add(intToUint32LE(0));

    var count = 0;

    void writeComment(String name, List<String> data) {
      for (var d in data) {
        count++;
        final toWrite = utf8.encode("$name=$d");
        commentsBuilder.add(intToUint32LE(toWrite.length));
        commentsBuilder.add(toWrite);
      }
    }

    writeComment("TITLE", metadata.title);
    writeComment("VERSION", metadata.version);
    writeComment("ALBUM", metadata.album);
    writeComment(
        "TRACKNUMBER", metadata.trackNumber.map((e) => e.toString()).toList());
    writeComment("ARTIST", metadata.artist);
    writeComment("ALBUMARTIST", metadata.albumArtist);
    writeComment("PERFORMER", metadata.performer);
    writeComment("COPYRIGHT", metadata.copyright);
    writeComment("LICENSE", metadata.license);
    writeComment("ORGANIZATION", metadata.organization);
    writeComment("DESCRIPTION", metadata.description);
    writeComment("GENRE", metadata.genres);
    // ISO 8601, slashes are jected by a lot of taggers and Android MediaStore
    writeComment(
        "DATE",
        metadata.date
            .map((d) =>
                "${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}")
            .toList());
    writeComment("LOCATION", metadata.location);
    writeComment("CONTACT", metadata.contact);
    writeComment("ISRC", metadata.isrc);
    // HomeTunes: disc number and lyrics were not written, and every other
    // comment (ReplayGain, composer, MusicBrainz ids…) was dropped. Write
    // those two and carry the rest over unchanged.
    if (metadata.discNumber != null) {
      writeComment("DISCNUMBER", ["${metadata.discNumber}"]);
    }
    if (metadata.lyric != null && metadata.lyric!.isNotEmpty) {
      writeComment("LYRICS", [metadata.lyric!]);
    }
    for (final c in keptVorbisComments(old, dropYear: metadata.date.isNotEmpty)) {
      count++;
      commentsBuilder.add(intToUint32LE(c.length));
      commentsBuilder.add(c);
    }

    mainBuilder.add(intToUint32LE(count));
    mainBuilder.add(commentsBuilder.toBytes());

    return mainBuilder.takeBytes();
  }
}

/// HomeTunes: comment names the FLAC writer writes from the metadata (or that
/// the written ones replace). Others are carried over from the old block.
const _managedVorbisComments = {
  'TITLE', 'VERSION', 'ALBUM', 'TRACKNUMBER', 'ITUNES_CDDB_TRACKNUMBER',
  'ARTIST', 'ALBUMARTIST', 'ALBUM_ARTIST', 'PERFORMER', 'COPYRIGHT',
  'LICENSE', 'ORGANIZATION', 'PUBLISHER', 'DESCRIPTION', 'GENRE', 'DATE',
  'LOCATION', 'CONTACT', 'ISRC', 'DISCNUMBER', 'LYRICS',
  'METADATA_BLOCK_PICTURE',
};

/// HomeTunes: the raw `NAME=value` comments of an old Vorbis comment block
/// that the writer doesn't manage.
List<Uint8List> keptVorbisComments(Uint8List? block, {bool dropYear = false}) {
  if (block == null || block.length < 8) return const [];
  final view = ByteData.sublistView(block);
  var pos = 4 + view.getUint32(0, Endian.little); // skip the vendor string
  if (pos + 4 > block.length) return const [];
  final count = view.getUint32(pos, Endian.little);
  pos += 4;
  final kept = <Uint8List>[];
  for (var i = 0; i < count && pos + 4 <= block.length; i++) {
    final len = view.getUint32(pos, Endian.little);
    pos += 4;
    if (pos + len > block.length) break;
    final raw = Uint8List.sublistView(block, pos, pos + len);
    pos += len;
    final eq = raw.indexOf(0x3D); // '='
    if (eq <= 0) continue;
    final name = String.fromCharCodes(raw.sublist(0, eq)).toUpperCase();
    if (_managedVorbisComments.contains(name)) continue;
    if (dropYear && name == 'YEAR') continue;
    kept.add(Uint8List.fromList(raw));
  }
  return kept;
}
