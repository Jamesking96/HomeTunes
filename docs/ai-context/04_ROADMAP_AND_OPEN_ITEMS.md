# Roadmap and open items

## The agreed plan: "HomeTunes Sound & Offline Plan"
The plan is published as an artifact (https://claude.ai/artifact/QsNhvBvSRx69PNvz3ULyjp). The
order is: 1 gapless (+ReplayGain) → 2 lyrics → 3 equaliser → 4 offline server songs.

| Phase | Status |
|---|---|
| 0: engine check | Done on Windows: libmpv has `equalizer`/`superequalizer`, `replaygain` and gapless. **Android's libmpv filters are not verified yet**, so check them before phase 3. |
| 1: gapless + ReplayGain | Done, in `main` |
| 2: lyrics (incl. "Find lyrics on LRCLIB" any time) | Done, merged |
| Book sidecar files (asked for by the user between phases) | Done, merged |
| **3: equaliser** | **Next** |
| 4: offline copies of server songs | After the server review |

### Phase 3: equaliser (from the plan)
- **Controls:** ten bands (31 Hz–16 kHz, ±12 dB) plus a pre-amp, and an on/off switch to compare.
- **Presets:** Flat, Bass boost, Treble boost, Vocal, Rock, Pop, Classical, Spoken word and
  Headphones, plus the user's own saved presets.
- **Behaviour:**
  - Changes are heard live, without restarting the song. Use media_kit's free `af` property with
    lavfi `equalizer` filters through `NativePlayer.setProperty`. media_kit only uses `af` for
    pitch, which HomeTunes doesn't use.
  - It must still work when the speed changes.
  - An optional separate setting for audiobooks (e.g. "Spoken word"), switched automatically.
- **Where it lives:** its own screen, reached from Settings and from a Now Playing button.
  Presets go into backups.
- **Open questions to ask first:** ten bands with presets, or presets only? A separate
  audiobook setting, yes or no?

### Phase 4: offline server songs
- **Needs first:** the server review.
- **Downloading:** download a song, album, playlist or Liked Songs. A "Keep offline" option
  follows albums and playlists. The quality is either the original or a server-converted copy.
- **Downloads screen:** progress, pause/retry, space used, delete.
- **Playback:** a downloaded copy plays first. Offline mode happens automatically when the server
  can't be reached.
- **Phone:** Wi-Fi-only, a storage limit, and downloads that continue in the background.
- **Backups:** list what's kept offline, but not the files themselves.
- **Open questions:** the quality choice, and whether to add crossfade (it would need two players).

## Needs reviewing with the user
- **Server review:**
  - Which server software the user runs.
  - How audiobooks on the server should work: `bookKey` for server files uses album + author.
  - Whether the server can transcode.
  - Noted since the audiobooks plan.
- **Android and sidecar files:** the media permission hides jpg/json/txt/pdf. Options are an
  opt-in "All files access" (MANAGE_EXTERNAL_STORAGE, fine for sideloading) or leaving it as is.
  Ask before adding.

## Known issues / small things
- **Dune collection tags are poor.** Many books show as "The New Dune Chronicles", with series
  taken from folder names like "01 - Dune Saga". The data itself is at fault, and the user can fix
  it with Edit book. Smarter guessing from folders would be possible.
- **VS Code F5 debug run on Windows can close after the scan.** Release is fine. This is parked.
- **Some tags are rewritten by the library, not preserved:**
  - The patched ID3 writer rewrites `TLEN` from the parsed duration, which may be slightly off for
    short files.
  - The FLAC vendor string is emptied.
  - Neither matters for playback.
- **iOS:** there's no local folder access, only server streaming. The server password is stored
  in plain text in the settings file.

## Offered earlier, not done (only if the user wants)
- Delete old installers in `build\dist` (0.1.0/0.1.2/0.1.3).
- GitHub Releases + Obtainium, so the phone can update itself.
- A sleep-timer button in the Android notification.

## Source control
All work is committed and pushed to GitHub (`main`). There are no uncommitted changes and no
other branches. Builds (`build\dist`) are not in git; they are rebuilt from source with the
commands in `02_…`.
