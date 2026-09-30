# Checks that every Material icon the app uses made it into the release build's icon font.
# Flutter's release build keeps only the icons it finds in the code ("icon tree shaking"); on
# 30 Sep it missed the ones in files whose code used a switch on a record, so those buttons
# were blank. Run after a Windows release build:
#   python tool\check_icons.py
# Lists any icon used in lib\ (or in media_kit_video's controls) that the built font lacks.
import os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, 'build', 'windows', 'x64', 'runner', 'Release', 'data', 'flutter_assets', 'fonts',
                    'MaterialIcons-Regular.otf')
SDK_ICONS = os.path.join(os.path.expanduser('~'), 'flutter', 'packages', 'flutter', 'lib', 'src', 'material', 'icons.dart')
MEDIA_KIT = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Pub', 'Cache', 'hosted', 'pub.dev', 'media_kit_video-2.0.1', 'lib')


def cmap(path):
    d = open(path, 'rb').read()
    n = struct.unpack('>H', d[4:6])[0]
    tables = {}
    for i in range(n):
        tag, _, off, _ = struct.unpack('>4sIII', d[12 + 16 * i:28 + 16 * i])
        tables[tag] = off
    c = tables[b'cmap']
    cps = set()
    for i in range(struct.unpack('>H', d[c + 2:c + 4])[0]):
        _, _, off = struct.unpack('>HHI', d[c + 4 + 8 * i:c + 12 + 8 * i])
        s = c + off
        fmt = struct.unpack('>H', d[s:s + 2])[0]
        if fmt == 12:
            for g in range(struct.unpack('>I', d[s + 12:s + 16])[0]):
                a, b, _ = struct.unpack('>III', d[s + 16 + 12 * g:s + 28 + 12 * g])
                cps.update(range(a, b + 1))
        elif fmt == 4:
            segx2 = struct.unpack('>H', d[s + 6:s + 8])[0]
            ends = struct.unpack('>%dH' % (segx2 // 2), d[s + 14:s + 14 + segx2])
            starts = struct.unpack('>%dH' % (segx2 // 2), d[s + 16 + segx2:s + 16 + 2 * segx2])
            for a, b in zip(starts, ends):
                if a != 0xFFFF:
                    cps.update(range(a, b + 1))
    return cps


codepoints = {}
for m in re.finditer(r'static const IconData (\w+) = IconData\((0x[0-9a-f]+)', open(SDK_ICONS, encoding='utf-8').read()):
    codepoints[m.group(1)] = int(m.group(2), 16)

used = {}
for base in [os.path.join(ROOT, 'lib'), MEDIA_KIT]:
    for dirpath, _, files in os.walk(base):
        for f in files:
            if f.endswith('.dart'):
                text = open(os.path.join(dirpath, f), encoding='utf-8').read()
                for name in re.findall(r'\bIcons\.(\w+)', text):
                    used.setdefault(name, set()).add(os.path.relpath(os.path.join(dirpath, f), base))

have = cmap(FONT)
missing = [(n, sorted(fs)) for n, fs in sorted(used.items()) if n in codepoints and codepoints[n] not in have]
print('%d icons used, %d in the font, %d missing' % (len(used), len(have), len(missing)))
for n, fs in missing:
    print('  MISSING', n, '-', ', '.join(fs))
sys.exit(1 if missing else 0)
