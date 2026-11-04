# Profiles plan

4 Nov 2026 · plan only, no code yet. The user: "create a plan for supporting profiles, this should
be an optional system that can be turned on via the settings page, where everything we do is split
between profiles."

## What it is

Profiles let several people share one HomeTunes (the family PC, the Family room TV) and each keep
their own place in everything: what they've watched, where they are in a book, their playlists and
Liked Songs, their favourites, their Home page, their look. It's **off by default**. With it off,
HomeTunes works exactly as it does today and nothing on screen or on disk changes.

Turning it on in **Settings › Profiles** makes the first profile out of everything there is now
(nothing is lost or reset), and from then on HomeTunes asks "Who's listening?" or remembers the last
one, depending on a setting.

## The rule for what's split

"Everything we do is split between profiles" is read as: **anything that records what a person did
or chose is theirs; the library itself is shared.** A song file, a video, an audiobook, the
folders, the servers and the corrections made to their details belong to the household, so a
cover fixed once is fixed for everyone and a rescan isn't needed per person. The table is the plan's
centre; open questions below mark the rows worth confirming.

| Data (file today) | Shared or per profile | Why |
|---|---|---|
| Songs, books, videos found (`library.json`, the scanned part of `videos.json`, `server_videos.json`, `server_books.json`) | Shared | The same files for everyone; scanning once |
| Edits to details: songs, books, videos, collections, season titles, special seasons, pictures, posters, picture shapes, genres found online (`edits.json`, parts of `videos.json`, `art/custom`) | Shared (open question 1) | A correction is a fact about the file, not a taste |
| Lyrics found online (`lyrics.json`) | Shared | A cache |
| Folders, file types, book rules, servers and their addresses (`settings.json` FolderSettings / ServerSettings, `servers.json`) | Shared | The device's set-up |
| Online look-ups switches (OnlineSettings) | Shared | Privacy choice for the device |
| Downloaded files, the download folder, Wi-Fi only, space limit, temporary copies (`downloads.json`, the files) | Shared, per device | One copy of each file on the disk |
| What's kept offline (`downloads.json` › kept) | Per profile, files shared | Each person keeps their own shows; a file stays while anyone keeps it |
| Watched / places in videos, video favourites, audio & subtitle choices, collection speeds, shuffle choices (`videos.json` › places, favourites, trackChoices, speeds, shuffle) | Per profile | What a person did |
| Book places, finished, speed per book (`listening.json`) | Per profile | |
| Bookmarks (`bookmarks.json`) | Per profile | |
| Playlists, Liked Songs, favourite albums / books / series (`playlists.json`) | Per profile (open question 2) | |
| Recently played music (`history.json`), so Home's Jump back in | Per profile | |
| Equaliser presets and choices (`equalizer.json`) | Per profile | Ears differ |
| Theme, text size, corners, saved themes (AppearanceSettings) | Per profile | Also shows whose profile is on |
| Playback, listening, video and sleep settings (PlaybackSettings, ListeningSettings, VideoSettings: skips, speeds, subtitle size, sleep lengths, volume boost) | Per profile, except "Smoother video on phones" (device) | |
| Sidebar quick links, sidebar width / folded, Artists grid (LayoutSettings) | Quick links per profile; width / folded per device | |
| Artist pictures, series details (LayoutSettings › artistPictures, seriesInfo) | Shared | They're edits |
| Words typed on the TV keyboard (`tv_words.json`) | Per profile | |
| Updates, What's new, Playback log (`updates.json`, `playback-log.txt`) | Device | |
| Server sign-ins (Jellyfin, Audiobookshelf, Subsonic) | Per profile when given, else the shared one | See "Server accounts" |

## Where things are saved

Today every file sits in the data folder. With profiles on:

```
hometunes/
  profiles.json                 profiles on/off, the list, the device's choices (new)
  settings.json                 device and shared settings only (personal ones move out)
  library.json, edits.json, lyrics.json, videos.json (shared part), servers.json,
  downloads.json, server_videos.json, server_books.json, art/      (unchanged)
  profiles/
    p1/  settings.json  playlists.json  listening.json  bookmarks.json  history.json
         equalizer.json  video_places.json  tv_words.json  kept.json
    p2/  ...
```

`profiles.json`: `{"on": true, "profiles": [{"id": "p1", "name": "James", "colour": "#FF7A59",
"icon": "headphones"}, …], "last": "p1", "ask": "start"}`. Ids never change (a rename changes the
name only). Pictures for a profile go in `art/profiles/`.

With profiles **off**, the personal files stay where they are today (no `profiles/` folder), so a
user who never turns it on has exactly today's layout. Turning it on moves the personal files into
`profiles/p1/` in one step (copy, check, then delete the originals; a crash part-way leaves the
originals, so it just runs again).

## How the code would change

The layer rules stay as they are. The work is mostly in `state/` and `services/storage.dart`.

1. **Two places to save.** `Storage` gets a `ProfileStorage` view: the same safe writes, rooted at
   `profiles/<id>/` (or the data folder itself when profiles are off). Each model is given the
   storage its file belongs to. Nothing else about saving changes.
2. **Settings know their scope.** `Setting` gets `scope: SettingScope.device | shared | profile`.
   `AppSettings` writes device and shared ones to the root `settings.json` and profile ones to the
   profile's. `refactor_safety_test.dart` gains a check that every setting has a scope and that
   on → off → on gives back the same files.
3. **videos.json is split.** `VideoLibraryModel` keeps the library and the edits; a new
   `VideoPlacesModel` (`video_places.json`) owns places, watched, favourites, track choices,
   speeds and shuffle choices. Today's methods (`placeOf`, `setWatched`, `isFavourite`…) stay on
   `VideoLibraryModel` and pass through, so screens don't change. This step is worth doing on its own
   first (phase 0): it changes nothing on screen.
4. **ProfilesModel** (`state/profiles_model.dart`, `profiles.json`): on/off, the list, add, rename,
   recolour, remove, the current one, "ask at start", `switchTo(id)`.
5. **Switching.** `switchTo` pauses music and videos, saves the leaving profile's places (the same
   flush as going to the background), then **rebuilds the personal models** for the new profile and
   hands them to the UI. The shared models (LibraryModel, VideoLibraryModel, ServersModel,
   DownloadsModel, the server readers) stay as they are, so there's no rescan or resync. In
   `main.dart` the personal models move into a `ProfileSession` object; `HomeTunesApp` puts its
   providers under a key of the profile's id, so every screen starts afresh on the new profile's data
   (each tab back to its first page). The queue is emptied: playing another person's queue would be
   odd.
6. **Who follows the change.** `SongIdFollower` (playlists, places, bookmarks, lyrics following moved
   files) must update every profile, not just the current one: followers for the others are loaded,
   updated and saved in the background when a rescan moves files. The same for forgetting a server's
   videos. A test covers a moved song staying in a playlist of a profile that wasn't on.
7. **Media controls and the TV.** `media_session.dart` and the notification show whatever the current
   profile plays; nothing else changes. Android Auto (later) uses the current profile.

## Server accounts

Watched and places already sync both ways with Jellyfin and Audiobookshelf. If everyone shared one
server account, profiles would split here but the server would mix them, and syncing would undo the
split. So each server entry in Settings › Servers gets **"Sign in per profile"**:

- Off (the default): one sign-in, as today; places sync for one profile only (the first, or one
  chosen as the server's profile). The others keep their places here only.
- On: each profile signs in with their own user on that server (Jellyfin and Audiobookshelf both
  have users). Tokens are kept in protected storage under server + profile (`secret_store.dart`
  already keys by server and user). The catalogue is still read once (shared); only places and
  watched sync per profile, through that profile's token.

Subsonic (music) has no places, only stars; stars could follow the profile's own login in the same
way, later.

## What the user sees

- **Settings › Profiles** (new page, A–Z between Playback and Servers): Use profiles (off); when on,
  the profiles as cards (name, colour, icon) with Add, Rename, Colour, Remove (asks; offers to merge
  into another profile instead); "When HomeTunes opens: ask who's using it / use the last one"; and
  per device "Start with" a profile. Turning it off asks which profile's things to keep using; the
  others are kept on disk and come back if it's turned on again.
- **PC:** the profile's picture at the top of the sidebar; click for the list and Switch. The
  window title says the name.
- **Phone:** the picture on Home's top bar; tap to switch.
- **TV:** "Who's watching?" full screen at start when asked for (big cards, the remote on the last
  one), and Switch profile in the TV menu. Back on the picker leaves the app, as on Home.
- Each profile's colour is its theme's accent unless they pick a theme, so it's clear whose it is.
- Backups (Settings › Backup) include every profile; restoring onto a device with profiles off
  turns them on. Later maybe "Back up just me".

## Optional extras (later, the user's call)

- **A child's profile:** only chosen categories, collections or folders show (the Videos type tabs
  and the existing folder rules make this mostly filtering); no Settings, no deleting, no
  downloads. Leaving it, or opening a grown-up profile, needs a PIN. PINs are stored as a salted hash,
  never plain.
- **A guest profile:** nothing it does is saved.
- Per-profile Home sections and sidebar order.

## Order of work

Each step is its own branch and release, tested on the PC, the phone and the Family room TV.

| Phase | What | Visible change |
|---|---|---|
| 0 | Groundwork: `ProfileStorage`, setting scopes, `videos.json` split into `video_places.json`, `ProfileSession` in `main.dart` with one built-in profile | None (`compare_previews.ps1` must match) |
| 1 | Profiles on PC and phone: Settings › Profiles, turning on / off with the move, add / rename / remove, switching from the sidebar and Home | Yes |
| 2 | The TV: Who's watching?, Switch profile in the menu | Yes |
| 3 | Server accounts per profile (Jellyfin, Audiobookshelf) | Yes |
| 4 | Child's profile and PINs (if wanted) | Yes |

Tests to add: `profiles_model_test.dart` (add, rename, remove, switch, on → off → on round trip),
`profile_storage_test.dart` (the move on turning on, a crash part-way, damaged `profiles.json`),
`profile_switch_test.dart` (a video's place saved to the right profile across a switch; playlists,
Liked Songs, Home's Jump back in and the theme follow; the queue empties), additions to
`refactor_safety_test.dart`, `downloads_test.dart` (a file kept while any profile keeps it) and the
server tests (places synced through each profile's token).

## Questions for the user before phase 1

1. Should edits to details (titles, genres, pictures, season titles) be shared by everyone, as
   planned, or per profile?
2. Playlists: each person's own (planned), or shared playlists everyone can see plus their own?
3. When HomeTunes opens: ask every time, or carry on as the last person (choosable per device, as
   planned)? Different on the TV?
4. Do you want a child's profile with a PIN (phase 4), or is it everyone trusted?
5. Will each person have their own Jellyfin and Audiobookshelf user, or one shared account?
6. Which version: the next 0.2.x builds, or start 0.3.0 for profiles?
