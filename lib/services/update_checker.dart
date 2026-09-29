// Looks for a newer HomeTunes on the GitHub Releases page and, on Windows, fetches the installer.
//
// UpdateModel (state/update_model.dart) drives this; Settings › About shows it. The check reads
// GitHub's "latest release" (drafts and pre-releases are never offered). On Windows, when
// HomeTunes was installed with the installer, [downloadInstaller] fetches HomeTunes-Setup-<v>.exe
// and the release's SHA256SUMS file and refuses the installer unless its checksum matches;
// [startInstaller] then runs it silently (it closes HomeTunes, updates it and starts it again —
// see /RELAUNCH in installer/hometunes.iss). Everywhere else (the phone, or the portable zip)
// [openInBrowser] opens the release page so the user can download it themselves. Added in 0.1.23.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Where HomeTunes' builds are published.
const releasesRepo = 'Jamesking96/HomeTunes';

/// The page listing every release, for when there's no single release to point at.
final releasesPage = Uri.parse('https://github.com/$releasesRepo/releases');

/// A problem the user can read ("Couldn't reach GitHub…").
class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

/// The newest published release.
class ReleaseInfo {
  /// Version number without the "v", e.g. "0.1.23".
  final String version;

  /// The release's web page.
  final Uri page;

  /// The "What's new" text from the release page, as plain text (may be empty).
  final String whatsNew;

  /// The same "What's new" text with its markdown kept (bullets, **bold**), for showing it
  /// formatted (0.1.28). Empty if the release page has no "What's new" part.
  final String notes;

  /// Download links by file name.
  final Map<String, Uri> assets;

  const ReleaseInfo(
      {required this.version, required this.page, required this.whatsNew, this.notes = '', required this.assets});

  /// Reads GitHub's release JSON. Null if it isn't a usable release.
  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (parseVersion(version) == null) return null;
    final pageText = json['html_url'];
    final page = (pageText is String ? Uri.tryParse(pageText) : null) ?? releasesPage;
    final assets = <String, Uri>{};
    final list = json['assets'];
    if (list is List) {
      for (final a in list) {
        if (a is! Map<String, dynamic>) continue;
        final name = a['name'];
        final url = a['browser_download_url'];
        final uri = url is String ? Uri.tryParse(url) : null;
        if (name is String && uri != null) assets[name] = uri;
      }
    }
    final body = json['body'];
    return ReleaseInfo(
      version: version,
      page: page,
      whatsNew: body is String ? whatsNewFrom(body) : '',
      notes: body is String ? whatsNewNotes(body) : '',
      assets: assets,
    );
  }

  /// The Windows installer's file name for this version.
  String get installerName => 'HomeTunes-Setup-$version.exe';

  /// The checksum list's file name for this version.
  String get checksumsName => 'HomeTunes-$version-SHA256SUMS.txt';
}

/// The "What's new" part of a release page as plain text: everything before the first `---`
/// line, without its heading and without markdown bold/code marks.
String whatsNewFrom(String body) => whatsNewNotes(body).replaceAll('**', '').replaceAll('`', '').trim();

/// The "What's new in x" part of a release page (everything before the first `---` line)
/// without its heading, markdown kept. Empty if the page doesn't start with that heading.
String whatsNewNotes(String body) {
  final text = body.replaceAll('\r\n', '\n');
  if (!text.trimLeft().startsWith("## What's new")) return '';
  final cut = text.indexOf('\n---\n');
  final part = cut < 0 ? text : text.substring(0, cut);
  final lines = part.trim().split('\n').skip(1); // drop the "## What's new in x" heading
  return lines.join('\n').trim();
}

/// The releases whose "What's new" should be shown after updating from [from] to [to]:
/// every release newer than [from], up to and including [to], newest first. With no [from]
/// (the old version isn't known), just [to]'s own release. Releases without notes are left out.
List<ReleaseInfo> releasesSince(Iterable<ReleaseInfo> all, {String? from, required String to}) {
  final picked = [
    for (final r in all)
      if (r.notes.isNotEmpty &&
          !isNewerVersion(r.version, to) &&
          (from == null ? !isNewerVersion(to, r.version) : isNewerVersion(r.version, from)))
        r,
  ];
  picked.sort((a, b) => isNewerVersion(a.version, b.version) ? -1 : (isNewerVersion(b.version, a.version) ? 1 : 0));
  // One entry per version (a tag like v0.1.27 and 0.1.27 would otherwise both show).
  final seen = <String>{};
  return [
    for (final r in picked)
      if (seen.add(parseVersion(r.version)!.join('.'))) r,
  ];
}

/// "0.1.23" or "0.1.23+23" as numbers ([0, 1, 23]); the build part after "+" is ignored.
/// Null if it isn't a version number.
List<int>? parseVersion(String v) {
  final core = v.trim().split('+').first.split('-').first;
  if (core.isEmpty) return null;
  final parts = <int>[];
  for (final s in core.split('.')) {
    final n = int.tryParse(s);
    if (n == null || n < 0) return null;
    parts.add(n);
  }
  return parts;
}

/// Whether [latest] is a newer version than [current] ("0.1.10" is newer than "0.1.9").
/// Anything that can't be read counts as not newer, so nothing is ever offered by mistake.
bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Reads a SHA256SUMS file (a 64-character checksum, spaces, then the file name, per line)
/// into file name → checksum.
Map<String, String> parseChecksums(String text) {
  final out = <String, String>{};
  final line = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$');
  for (final l in const LineSplitter().convert(text)) {
    final m = line.firstMatch(l.trim());
    if (m != null) out[m.group(2)!] = m.group(1)!.toLowerCase();
  }
  return out;
}

/// Only files from this repository's release downloads are ever fetched.
bool isReleaseDownload(Uri u) =>
    u.scheme == 'https' && u.host == 'github.com' && u.path.startsWith('/$releasesRepo/releases/download/');

/// Talks to GitHub. [client] can be swapped for a fake in tests.
class UpdateChecker {
  final http.Client client;
  UpdateChecker({http.Client? client}) : client = client ?? http.Client();

  static const _headers = {'User-Agent': 'HomeTunes update check', 'Accept': 'application/vnd.github+json'};

  /// The newest published release.
  Future<ReleaseInfo> fetchLatest() async {
    final http.Response r;
    try {
      r = await client
          .get(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const UpdateException('Couldn\'t reach GitHub. Check the internet connection and try again.');
    }
    if (r.statusCode == 403 || r.statusCode == 429) {
      throw const UpdateException('GitHub is busy right now. Try again in a little while.');
    }
    if (r.statusCode != 200) throw UpdateException('GitHub didn\'t answer as expected (error ${r.statusCode}).');
    final info = ReleaseInfo.fromJson(_decode(r.body));
    if (info == null) throw const UpdateException('The latest release on GitHub couldn\'t be read.');
    return info;
  }

  /// The most recent published releases (up to 50, newest first), for the "What's new" list
  /// shown after an update (0.1.28). Drafts, pre-releases and odd tags are left out.
  Future<List<ReleaseInfo>> fetchReleases() async {
    final http.Response r;
    try {
      r = await client
          .get(Uri.parse('https://api.github.com/repos/$releasesRepo/releases?per_page=50'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const UpdateException('Couldn\'t reach GitHub. Check the internet connection.');
    }
    if (r.statusCode == 403 || r.statusCode == 429) {
      throw const UpdateException('GitHub is busy right now. Try again in a little while.');
    }
    if (r.statusCode != 200) throw UpdateException('GitHub didn\'t answer as expected (error ${r.statusCode}).');
    final list = _decode(r.body);
    if (list is! List) throw const UpdateException('The list of releases on GitHub couldn\'t be read.');
    return [
      for (final j in list) ?ReleaseInfo.fromJson(j),
    ];
  }

  static Object? _decode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// True when this copy can update itself: Windows, installed with the installer (the
  /// uninstaller sits next to the program). The portable zip and the phone can't.
  static bool get canInstallHere {
    if (!Platform.isWindows) return false;
    final dir = p.dirname(Platform.resolvedExecutable);
    return File(p.join(dir, 'unins000.exe')).existsSync();
  }

  /// Downloads the Windows installer for [release] into a temporary folder and checks it
  /// against the release's checksum list. [onProgress] gets 0–1 (or null while the size is
  /// unknown). Throws [UpdateException] if anything is missing or doesn't match.
  Future<File> downloadInstaller(ReleaseInfo release, {void Function(double? fraction)? onProgress}) async {
    final installerUrl = release.assets[release.installerName];
    final sumsUrl = release.assets[release.checksumsName];
    if (installerUrl == null || !isReleaseDownload(installerUrl)) {
      throw const UpdateException('This release has no Windows installer.');
    }
    if (sumsUrl == null || !isReleaseDownload(sumsUrl)) {
      throw const UpdateException('This release has no checksum file, so the download can\'t be checked.');
    }
    // 1. The checksum list (small).
    final String sumsText;
    try {
      final r = await client.get(sumsUrl, headers: const {'User-Agent': 'HomeTunes update check'})
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      sumsText = utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (_) {
      throw const UpdateException('Couldn\'t download the checksum file. Try again.');
    }
    final expected = parseChecksums(sumsText)[release.installerName];
    if (expected == null) throw const UpdateException('The checksum file doesn\'t list the installer.');

    // 2. The installer, streamed to disk.
    final dir = Directory(p.join(Directory.systemTemp.path, 'HomeTunes-update'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, release.installerName));
    final sink = file.openWrite();
    var ok = false;
    try {
      final req = http.Request('GET', installerUrl)..headers['User-Agent'] = 'HomeTunes update check';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      onProgress?.call(total == null || total <= 0 ? null : 0);
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
      }
      ok = true;
    } catch (_) {
      throw const UpdateException('The download didn\'t finish. Check the internet connection and try again.');
    } finally {
      await sink.close();
      if (!ok && await file.exists()) await file.delete();
    }

    // 3. Check it's exactly the file that was published.
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      await file.delete();
      throw const UpdateException('The downloaded installer didn\'t match its checksum, so it wasn\'t used. '
          'Try again later.');
    }
    return file;
  }

  /// Runs [installer] silently, on its own. It waits for HomeTunes to close, updates it and
  /// starts it again. The caller should close HomeTunes straight after.
  static Future<void> startInstaller(File installer) async {
    await Process.start(
      installer.path,
      const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RELAUNCH=1'],
      mode: ProcessStartMode.detached,
    );
  }

  static const _appChannel = MethodChannel('hometunes/app');

  /// Opens [url] in the web browser. Returns false if that didn't work.
  static Future<bool> openInBrowser(Uri url) async {
    if (url.scheme != 'https') return false;
    try {
      if (Platform.isAndroid) {
        await _appChannel.invokeMethod<void>('openUrl', {'url': url.toString()});
        return true;
      }
      if (Platform.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url.toString()]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [url.toString()]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url.toString()]);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
