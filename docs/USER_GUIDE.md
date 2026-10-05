# HomeTunes: download and user guide

HomeTunes is a music and audiobook player for **your own files**, a bit like Spotify and Audible
but using music you already have. Point it at the folder where your music lives and it builds a
library of artists, albums, songs and audiobooks. You can also stream from your own music server
(Navidrome or another Subsonic server) if you have one.

It runs on **Android phones** and **Windows PCs**. There's no iPhone or Mac download.

![The HomeTunes Home screen on a Windows PC, showing Continue listening, Shuffle all, Liked Songs and Recently added albums](images/home-pc.jpg)

---

## 1. Which file do I download?

Go to the [Releases page](https://github.com/Jamesking96/HomeTunes/releases). The newest version is
marked **Latest**. Under **Assets**, pick the file for your device:

| Your device | Download | What it is |
| --- | --- | --- |
| Android phone or tablet | `HomeTunes-<version>-android.apk` | The phone app |
| Windows PC (recommended) | `HomeTunes-Setup-<version>.exe` | Installer: adds HomeTunes to the Start menu |
| Windows PC (no install) | `HomeTunes-<version>-windows.zip` | A folder you can run from anywhere, even a USB stick |

Ignore the two "Source code" files. They're the code for developers, not the app.

**Checking a download (optional):** the release page ends with a **Checksums (SHA-256)** list, also
attached as `HomeTunes-<version>-SHA256SUMS.txt`. On Windows, open PowerShell in your Downloads
folder and run `Get-FileHash HomeTunes-Setup-<version>.exe` (use the name of the file you
downloaded). The long code it prints should match that file's line in the list (capital or small
letters don't matter). If it doesn't, delete the file and download it again.

---

## 2. Installing on an Android phone

1. **On the phone**, open the Releases page in your browser and tap the `.apk` file to download it.
   (Or download it on a PC and copy it to the phone's Downloads folder.)
2. When it finishes, tap the download (in the browser's downloads or the **Files** app).
3. The first time, Android asks whether to allow installing apps from this source. Tap
   **Settings**, turn on **Allow from this source**, then go back.
4. Tap **Install**. If Google Play Protect says the app is from an unknown developer, tap
   **More details › Install anyway**. HomeTunes isn't on the Play Store, so this is expected.
5. Open HomeTunes. When it asks to access **music and audio**, tap **Allow**. Without this it
   can't see your music.

**Coming from 0.1.20 or earlier:** version 0.1.21 is signed with HomeTunes' own key instead of a
temporary one, so Android won't install it over an older version (it says the app conflicts
with an existing one). This happens only once:
1. In the old version, go to **Settings › Backup & restore**, export a backup and save the file in
   **Downloads**.
2. Uninstall HomeTunes, then install the new `.apk`.
3. Open it, go to **Settings › Backup & restore › Import backup…**, pick the file and choose
   **Replace**.
4. If you use a music server, type its password again in **Settings › Servers**.

After that, every update installs over the top as normal.

**Updating:** go to **Settings › About › Check for updates** (from version 0.1.23). If there's a
newer version, tap **Update…** then **Open download page** to go to it in your browser: download
the `.apk` and open it to install over the top. (Or download the newer `.apk` from the Releases
page yourself.) Don't uninstall first: your library, playlists, places in books and settings are
all kept.

---

## 3. Installing on a Windows PC

### With the installer (recommended)
1. Download `HomeTunes-Setup-<version>.exe` and open it.
2. If Windows shows **"Windows protected your PC"**, click **More info › Run anyway**. The app
   isn't signed with a paid certificate, so Windows doesn't recognise it yet.
3. Follow the steps. No administrator password is needed; it installs just for you unless you
   choose otherwise. You can tick **Create a desktop shortcut** if you want one.
4. Start HomeTunes from the Start menu.

**Updating:** from version 0.1.23, go to **Settings › About › Check for updates**. If there's a
newer version, click **Update…** and then **Update**: HomeTunes downloads it, checks the file,
closes, updates itself and opens again. (Or run the newer installer yourself.) Your library and
settings are kept.
**Uninstalling:** Windows Settings › Apps › HomeTunes › Uninstall. This removes the program only:
your library, playlists and settings stay on the PC, so reinstalling picks up where you left off.

### Without installing (zip)
1. Download `HomeTunes-<version>-windows.zip`.
2. Right-click it › **Extract All…**, and choose where to put the folder.
3. Open the folder and double-click `hometunes.exe`. Keep all the files together; the app needs
   them.

A copy run from the zip can tell you when there's a new version, but can't update itself: it
opens the download page instead.

---

## 4. First steps

### Add your music
1. The Home screen says **No music yet**. Tap **Add music**, which opens **Settings › Folders &
   scanning**, then tap **Add folder** under **Music folders**.
2. Choose the folder where your music is kept. HomeTunes reads the details (artist, album, cover
   art…) from your files. The progress shows at the bottom of the screen.
3. Add more folders the same way. After adding new music to a folder, press **Rescan**.
4. Each folder has an options button (sliders icon). It opens **Folder options**, where you can
   **Rescan this folder** on its own, and under **File types** untick any kind of file you don't
   want from that folder (say, WAV copies). Unticked types disappear from your library at once;
   nothing is deleted, and ticking them again brings them back. Audiobook folders have the same
   options.

HomeTunes plays MP3, FLAC, M4A/AAC, OGG, Opus, WAV and M4B files. It never changes, moves or
deletes your music files.

### Audiobooks
Audiobooks appear in the **Books** tab (called **Audiobooks** on a PC). HomeTunes spots them by their genre (such as
"Audiobook"), `.m4b` files, or a folder called something like "Audiobooks". To make a whole folder
count as books, go to **Settings › Folders & scanning** (or **Settings › Audiobooks**) and use **Add audiobook folder**. Books remember where
you got to, and **Continue listening** on the Home screen picks up where you left off.

If something lands in the wrong place, a song's menu has **Move to Books**, and a book's page has
**Move to Music…**. While a book plays, Now Playing has skip back and forward buttons, a speed
button, **Chapters** and **Bookmarks** (and a button to bookmark the spot you're at). Skip
lengths, speed for new books and book cover shape are in **Settings › Audiobooks**.

### Videos
Go to **Settings › Folders & scanning** (or **Settings › Videos**) and use **Add video folder**.
HomeTunes plays MP4, MKV, WebM, AVI, MOV and most other video files, and shows them in the
**Videos** tab. Folders named like `TV`, `Anime` or `Films` become categories, the folder under
them becomes a collection (a series or a set of films), and `Season 1` folders and `S01E02`-style
file names give seasons and episodes. **Rescan videos** looks again after you add files; each video
folder has the same **Folder options** as a music folder. On a phone, HomeTunes asks for "Photos
and videos" access when you add a video folder.

A song with a video of the same name beside it (for example `Song.m4a` and `Song.mp4`) is a
**music video**: Now Playing shows it in place of the cover. **Settings › Music** can turn music
videos off, or keep the cover until you press the video button.

### Your own servers (optional)
If you run a music server such as Navidrome, go to **Settings › Servers**, choose **Add a server**,
pick **Subsonic** as the kind, enter its address (for example `http://192.168.1.20:4533`), your
username and password, then **Connect**. It becomes your **main music server**: its songs show a
small cloud icon and mix in with your own files. Audiobooks on it show in the Books tab too (turn
its switch off in the **Audiobooks** section to keep them out).

The Servers page has a section each for **Music**, **Audiobooks** and **Videos**, and you can add
as many servers as you like: Subsonic, Jellyfin, Plex, Emby, Audiobookshelf, or a HomeTunes
server. A server that has all three kinds shows in all three sections, with a switch in each to
use it for that kind. **Test connection** checks the server is there and what it is. For now
HomeTunes plays from **one Subsonic server at a time**; any others are kept, ready for when
playing from them is added (**Kinds of server** at the bottom of the page shows what works now).
To switch to another Subsonic server you've added, use its **⋮** menu › **Make this the main music
server**.

If you type an address without `http://` or `https://`, HomeTunes tries a secure (https)
connection first. If the server is on the internet and only answers over plain http, HomeTunes
asks before using it, because your sign-in could then be read on the way. Addresses on your home
network (and Tailscale addresses) connect without asking.

---

## 5. Everyday use

The main sections are **Home**, **Search**, **Library**, **Books**, **Videos** and **Settings**. On
a phone they're tabs along the bottom. On a PC they're down the left-hand side, where Library is
called **Your Library** and Books is called **Audiobooks**, with **Liked Songs**, **Favourite
audiobooks**, **Favourite videos** and your playlists underneath. Drag the sidebar's right-hand
edge to make it wider or narrower; the **☰** button at its top (or a double-click on the edge)
folds it down to icons and opens it again.

- **Home:** **Jump back in** at the top shows what you were last doing, newest first: videos and
  audiobooks you're part-way through, and the albums, playlists and artists you last played. The
  round play button on each carries on (or plays it again); tap the card itself to open it. Below
  are quick tiles (Shuffle all, Liked Songs, favourites, your playlists) and a section each for
  **Music**, **Audiobooks** and **Videos** (recently added, your favourites, and **Up next**: the
  next episode of a series you're watching). **See all** opens that tab. To clear the music
  you've played from Jump back in, use **Settings › Playback › Forget recently played music**.
- **Play something:** tap a song, album, playlist or book. The player bar at the bottom shows
  what's playing; tap it for the full **Now Playing** screen.

  ![The Now Playing screen on a PC, with the album cover, play controls and the lyrics panel](images/now-playing-pc.jpg)

  Under the controls are buttons for the **equaliser**, **lyrics** and the **queue** (what's
  playing next, which you can reorder). The queue slides in from the side over whatever you're
  looking at; tap outside it, swipe it away or press its ✕ to close it.
- **Lyrics:** HomeTunes shows a song's lyrics when it can find them (in the file, a `.lrc` file
  next to it, your music server, or online). Timed lyrics scroll along with the song.
- **Going online:** HomeTunes can look up missing covers, song details and lyrics online. Each
  can be switched off in **Settings › Online lookups**; only names (artist, album, song) are sent.
  If HomeTunes can't reach the internet when it opens, it tells you which features won't work
  and you can carry on. When you use one of those features later, it checks again; if you're
  still offline you get the same message (with **Try anyway** in case it's wrong).
- **On a phone:** swipe the player left or right to skip. The music keeps playing with the screen
  locked, and you can control it from the lock screen, the notification or headphone buttons.
- **On a PC:** your keyboard's media keys work.
- **Artist pages:** click an album to see its songs right underneath (click it again to close
  them). Right-click it (press and hold on a phone) and choose **Open album page** for the full
  page. On a PC, moving the mouse over any album cover shows a play button to play it straight
  away.
- **Artist pictures:** an artist shows their first album's cover until you choose something
  else. Click the round picture on their page (or the picture button beside Play and Shuffle),
  or right-click an artist anywhere (press and hold on a phone) and choose **Change picture…**:
  pick an image file, one of their album covers, or go back to the automatic picture.
- **Search:** finds songs, artists, albums, books, chapters, videos and video collections. Every
  word you type must match.
- **Playlists and favourites:** make playlists in **Library**, like songs with the heart, and
  heart whole albums or books. Library tabs have filters and sorting, including **Favourites**.
  On the **Artists** tab, the button beside the filter switches between a list and a grid of
  round pictures; HomeTunes remembers which you chose.
  Each list in the filter (artist, album, genre, author, collection and so on) has a search box
  at the top: type part of a name to find it, and press Enter to pick the first match.
- **Menus:** right-click (PC) or press and hold (phone) on an album or book for quick actions:
  **Edit details…**, **Choose cover…**, **Add to favourites** and **Details…** (where it came
  from). A song's menu has **Go to album**, **Go to artist**, **Edit details…**, **Lyrics** and
  **Details…**, among others.
- **Copying titles:** drag across the big title at the top of an album, artist, playlist, book,
  collection or video page (or on Now Playing) and copy it with Ctrl+C or a right-click. Songs,
  albums, books, videos and collections also have **Copy title** in their right-click menu.
- **Selecting several:** right-click (or press and hold) and choose **Select**, then tap others to
  tick them. On a PC, hold **Shift** and click to tick everything between the last one you
  clicked and this one; this works for songs, albums, books, videos, episodes and collections,
  and a Shift + click also starts selecting on its own. Press **Esc** (or the ✕ on the bar) to
  stop selecting.
- **Fix wrong details:** use **Edit details**. Select several albums or books to edit them together.
  Your changes are kept by HomeTunes and don't touch the files, unless you choose to save
  them into the files in **Settings › Your edits**.
  When you edit one song and change its album name or album artist, only that song moves; tick
  **Also update the other songs on "…"** if you want to rename the whole album instead. A
  changed year, genre or cover offers the same box, already ticked.
- **Equaliser:** in **Settings › Playback** or the button on Now Playing. Pick a preset or make
  your own. Audiobooks can use their own preset automatically.
- **Sleep timer:** the moon button next to the play controls stops playback after a set time or at the end of the chapter or song.
  Options are in **Settings › Sleep timer**.
- **Volume:** click the speaker icon beside any volume slider to mute; click it again to go back
  to the volume you had. The slider is in the player bar on a PC, under the play controls on Now Playing (with the
  cover or the lyrics showing), and the speaker button in the phone's mini player, which opens a
  small slider.
- **Videos:** the **Videos** tab has **Collections**, **All videos** and **Favourites**. Tap a
  collection to see its seasons underneath, or right-click it (press and hold on a phone) for
  **Open collection page**, **Edit collection…**, **Change poster…** and more. A video carries on
  where you stopped, and the next episode starts after a short countdown.
  - **Watching:** the player has skip buttons, **previous / next video**, speed, and a subtitles
    button for choosing audio and subtitle tracks (remembered for each collection). Below the
    video are **Enlarge**, **Full screen** and more. On a PC, Space, the arrow keys, F and Esc work,
    and the mouse wheel over any progress bar skips 5 seconds.
  - **While a video plays** the bottom bar shows it; tap its title to go back to it. Your media
    keys and the phone notification control it. Starting a video pauses your music, and starting
    music pauses the video.
  - **Tidying up:** **Edit details** works on one video or several (right-click › **Select**).
    Right-click a season's heading to select all of it, mark it watched, or give it a title
    (**Season 1 – Offline News**). Pictures can be changed with **Change picture…**: an image
    file, a frame from the video, or a search online.
  - **Details…** (in a video's or a collection's right-click menu, under the video player and the
    ⓘ on a collection's page) shows where the file is, where each detail came from (its file or
    folder name, an .nfo file, or your edit), and what's inside the file: its picture size and
    frame rate, each sound track and subtitle with its language, and its chapters.
  - **Settings › Videos** has the skip lengths, speed and the videos' equaliser.
    **Settings › Appearance › Video player** changes the player's buttons (colour, size, and a
    glow or circles behind them so they're easy to see on any scene).
- **Updates:** HomeTunes looks for a new version each time it opens and shows a notice with an **Update…**
  button if there is one. Check any time in **Settings › About › Check for updates**, where
  there's also a switch to turn the automatic check off.
- **What's new:** the first time HomeTunes opens after an update, it shows what changed, taken
  from the release pages: everything since the version you had, newest first (it needs the
  internet; if it can't connect, **Open release page** shows the same list in your browser). To
  see it again, go to **Settings › About › What's new in this version**.
- **Colours:** **Settings › Appearance** has three ready-made themes (Default, Midnight and Forest)
  and **Your own**, where you pick a highlight colour and a background colour. Tap a theme and
  the whole app changes straight away. Your choice is included in backups.
  Under **Advanced** you can make as many themes of your own as you like, choosing every colour
  (background, panels, raised panels, text, grey text, highlight, slider track and play button),
  including light themes with dark text. HomeTunes warns you if something would be hard to read.
  Each of your themes has **Edit** and **Delete** buttons (Delete is also inside the theme editor),
  and its **⋮** menu can also **Duplicate…** it.
  **Reset to default colours** puts "Your own" back to how it started (with Undo). **Advanced**
  also has **Text size** and **Corners** (from square to extra round).
  On a PC, **Shrink to fit small windows** (on to start with) makes buttons, text and pictures a
  little smaller when you make the window small, so more fits; turn it off to keep them full size.
  In any colour picker you can also type or paste a colour code such as `#FF7A59` into
  **Colour code** (the paste button beside it pastes straight in).
- **Sharing themes with friends:** a saved theme's **⋮ › Share…** (or **Share these colours**
  under Your own) shows a theme code: **Copy code** and paste it into a message, or **Save as
  file…** and send the file. Your friend goes to **Settings › Appearance › Import a theme**,
  pastes the code (the whole message is fine) or chooses **Open a file…**, sees the theme, and
  taps **Add and use**. Only the theme's name and colours are shared.
- **Licences:** HomeTunes is free and open source under the MIT License. **Settings › About ›
  Licences** lists it and the licences of everything it's built with.
- **Notices:** the messages that pop up at the bottom of the screen have a **✕** to close them
  straight away (beside **Undo** when there is one). Otherwise they close by themselves, after
  15 seconds at most.
- **Settings search:** type in the box at the top of Settings to find any option. The Settings
  tabs are in A–Z order; **Folders & scanning** has your music, audiobook and video folders.

---

## 6. Moving to a new device, and backups

**Settings › Backup & restore** saves everything HomeTunes keeps (folders, playlists, likes,
favourites, your edits, places in books and videos, video pictures and season titles,
bookmarks, equaliser and settings) into one `.htbackup`
file. Restore it on another phone or PC to carry it all across, then point HomeTunes at the music
folders on that device. Use **Export backup…** to make the file and **Import backup…** to restore
it. When restoring you choose **Replace** (this device's HomeTunes data becomes the backup's) or
**Merge** (the backup's playlists, likes and edits are added to what's already there).

Your music server password is **never** put in the backup file, so it can't be read by anyone who
gets hold of the file. After restoring on a new device, type it in once under **Settings ›
Servers**. (Restoring on the same device, with the same server, keeps it.)

On Android, HomeTunes doesn't use Google's automatic app backup. When you move to a new phone,
use a HomeTunes backup file as described above.

---

## 7. If something goes wrong

- **No music shows up on the phone:** check HomeTunes may access music. Android Settings ›
  Apps › HomeTunes › Permissions › **Music and audio** › Allow. Then **Rescan**.
- **Some songs are missing:** make sure their folder is listed in **Settings › Folders & scanning**, then
  press **Rescan**.
- **Playback stops or behaves oddly:** open **Settings › About › Playback log**, tap **Copy**, and
  send it along with a description of what happened.
- **A video or music video stutters:** the Playback log also notes, for each video, its size and
  format, how your device is decoding it, and (only when something goes wrong) how many
  pictures were dropped and whether it had to wait for the file. Play the video until it
  stutters, then copy the log the same way.
- **Windows won't start the app:** if you used the zip, make sure you extracted it first (don't run
  it from inside the zip).

The version you're running is shown in **Settings › About**.
