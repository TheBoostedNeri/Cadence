# Cadence

A native SwiftUI music player for iOS 26+ and macOS 26+ that browses YouTube with the official
**YouTube Data API v3** and plays songs in YouTube's official **IFrame player**, with
Liquid Glass throughout. There are no third-party dependencies.

## Features

- **Onboarding**: welcome, how playback works, and connecting a YouTube account (the only permission the app needs).
- **Home**: trending music for your region, plus "Jump Back In" from your history.
- **Search**: songs and music videos, with results that update as you type. Each YouTube search costs 100 quota units, so live search waits for a half-second pause and at least two characters, and reuses earlier results. Pressing Search searches right away.
- **Playlists**: your real YouTube playlists. Play, shuffle, create, add songs (long-press any song) and swipe to remove. Rename or delete a playlist from its page's ⋯ menu or by long-pressing it in Playlists (50 quota units each; Apple Music doesn't let apps rename or delete playlists, so it's YouTube only).
- **Discover**: what's trending on the selected service, swiped through in columns, then tiles for every genre (Pop, Rock, Hip-Hop/Rap, K-Pop, Jazz, Classical and more). A genre opens its best-selling songs in your region from Apple's free iTunes Store charts, which need no key or quota to load. They play on the selected service: on YouTube, each song's video is found as it comes up to play, like album songs (a search costs 100 quota units the first time a song plays, then the match is remembered).
- **Recents**: play history stored on the device with SwiftData, kept separately for each service.
- **Song menus**: every song in a list has a ⋯ button, like Apple Music, with the same actions as a long press: Play Next, Play Last, Add to Playlist, Go to Album, Go to Artist, Share and Open in YouTube or Apple Music. Songs from Apple's catalog (albums, artists and Discover's genres) can be added to YouTube playlists too: their video is found first, a 100-unit search the first time, plus YouTube's 50 units for each song added. Discover's genre and Trending lists have **Select**, to pick several songs and add them to a playlist together; songs YouTube has no video for are skipped and counted.
- **Queue**: long-press any song, or tap its ⋯, for **Play Next** or **Play Last**. In Up Next, long-press a song to move it up or remove it, or clear the whole list; on the Mac, drag songs into a new order and press Delete to remove one. Shuffle and Repeat (all, or one song) are in Up Next, the Mac player bar and the Playback menu. **Autoplay** keeps the music going when the queue runs out: it lines up similar music after everything you've queued: popular songs from the same genre in Apple's charts (Apple's "Hard Rock" counts as Rock, "Indie Pop" as Alternative, and so on), with about one in three by the same artist, tops them up as they play, and Up Next lists them in their own section below a divider (on YouTube each one is found when it plays, like album songs). Songs you add with Play Next or Play Last always go before Autoplay's, and turning Autoplay off takes its songs out. Editing Up Next, Shuffle and Repeat work on YouTube queues; the system Apple Music player keeps its own order, though Play Next and Play Last work there too.
- **Albums and artists**: long-press any song, or use the ⋯ menu in Now Playing, and choose **Go to Album** for the album it's from (Play, Shuffle and a numbered track list) or **Go to Artist** for an artist page laid out like Apple Music's: a large header with their name and Play, the latest release, Top Songs in columns of four you swipe through (See All lists every song, most popular first), and carousels of Albums, Singles & EPs, and releases they Appear On, each opening its album. Apple's free catalog has no artist photos, so the cover of their most popular song stands in. Tapping the artist on an album page opens the artist too, and pages stack, so you can go from album to artist to another album and back. YouTube's API has neither albums nor artists, so both come from Apple's free iTunes catalog for every service. Apple Music songs play as they are. On YouTube, each album song's video is found when it's about to play: one YouTube search (about 100 quota units) per song, preferring the artist's auto-generated "Topic" channel, which carries the album audio. Each match is remembered on the device, so a song is never searched for twice.
- **Now Playing**: laid out like Apple Music on iPhone. It's always dark and tinted by the artwork's colors, with white text. The artwork (or YouTube's video) sits on top; wherever artwork stands in for video (Apple Music, and YouTube with background play on), it fills the top edge to edge and fades into the background. Below are the song with a star and ⋯ menu, a thin scrubber that thickens while you drag it, large Previous/Play/Next buttons, the volume slider, and Lyrics, AirPlay and Up Next along the bottom. Lyrics and Up Next swap in for the artwork, which steps down to a small header (tap it to go back). Up Next has Shuffle, Repeat and Autoplay on top, and handles for dragging songs into a new order; long-press a song to play it next or remove it. The star likes the song on your YouTube account, so it shows in Liked Music (50 quota units per like; it appears for YouTube videos while an account is connected). The mini player sits in the tab bar's bottom accessory; like Apple Music's, it shows "Not Playing" with greyed-out buttons when nothing is queued.
- **iPad**: a sidebar, multi-column song grids, playlists as a grid of artwork, and Now Playing in a panel beside the app so you can keep browsing. It adapts to every orientation and window size, and narrow windows get the iPhone layout. With a keyboard: Space plays or pauses, ⌘→ and ⌘← skip, ⌘L shows Now Playing, and ⌘1–4 and ⌘F switch tabs. Songs can be dragged into other apps as links.
- **Mac**: a native Mac app from the same code, laid out like Apple Music on the Mac. The player floats in a glass bar along the bottom of the content: Shuffle, Previous, Play, Next and Repeat on the left; the song in the middle, with its artwork, title, artist and album, and a thin progress bar you can click or drag (the times show while the pointer is over it); and Lyrics, Up Next and volume on the right. With nothing playing, the playback buttons grey out and a music note sits in the middle. Shuffle and Repeat (all, or one song) work on YouTube queues and carry over to the next list you play. Lyrics and Up Next open a panel on the right that matches the iPhone's lyrics and queue views: dark and tinted by the artwork, the YouTube video at the top (YouTube requires it to stay visible while playing), the song with its star and ⋯, then the lyrics, or Up Next with Shuffle, Repeat and Autoplay above songs you can drag into order or remove with Delete. Clicking a button again closes the panel, and clicking the artwork shows or hides it. The sidebar has search at the top, then Home and Discover, a Library section with Recently Played, and a Playlists section with All Playlists and every playlist by name. The Playback menu and its shortcuts are in the menu bar, and Settings has its own window (⌘,). It's a single window, because there's one player. It plays YouTube only: the Apple Music library and player APIs Cadence uses don't exist on macOS.

## Setup

1. Create `Config/Secrets.xcconfig` (it's git-ignored) and set the four values listed in `Config/Base.xcconfig`: `CADENCE_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, `YOUTUBE_API_KEY` and `GOOGLE_CLIENT_ID`.
2. In [Google Cloud Console](https://console.cloud.google.com/), create a project and enable **YouTube Data API v3**.
3. **API key** (for browsing without an account): create an API key, restrict it to *iOS apps* with your bundle ID and to *YouTube Data API v3*, then set `YOUTUBE_API_KEY`.
4. **OAuth client** (for playlists): configure the OAuth consent screen and add yourself as a test user. Create an OAuth client ID of type **iOS** with your bundle ID, then set `GOOGLE_CLIENT_ID`.
5. Set `CADENCE_BUNDLE_IDENTIFIER` to the same bundle ID. To run on a device, also set `DEVELOPMENT_TEAM`.
6. Open `Cadence.xcodeproj`, pick the **Cadence** scheme for iPhone and iPad or **CadenceMac** for the Mac, and run.

The Mac app uses the same bundle ID, API key and OAuth client as iOS. API requests send the bundle ID, so a key restricted to iOS apps works for the Mac app too.

The app runs without any of these and explains what's missing on each screen.

`Cadence.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
After adding or removing files, run `xcodegen generate`. You can also add the files in Xcode directly.

## Music services

Choose a service in **Settings → Music Service** (or during onboarding). Every tab follows the selected service and shows only its music, Recently Played and Home's "Jump Back In" included; each service's history is kept and comes back when you switch back.

| | YouTube Music (default) | Apple Music | Spotify |
|---|---|---|---|
| Catalog and charts | YouTube Data API | iTunes Search API and Apple Music charts feed (no key) | Planned |
| Your library | Google sign-in | Media & Apple Music permission (MediaPlayer) | Planned |
| Playback | Embedded YouTube player, video visible | System Apple Music player, background and Lock Screen | Planned (Spotify iOS SDK) |
| Needs | API key and/or OAuth client | Apple Music subscription; a real iPhone | Spotify Premium and app |

Apple Music is iPhone and iPad only; on the Mac it shows as unavailable. It runs without MusicKit, so it works with a free Apple developer account. It can't remove songs from playlists (MediaPlayer doesn't allow it), and it can't play in the Simulator.

## YouTube policy constraints (by design)

- The player is always visible while playing and is never smaller than 200×200 pt.
- Playback pauses when Now Playing is dismissed or the app goes to the background. There's no background or lock-screen audio.
- Account links to the YouTube Terms of Service, Google Privacy Policy and Google's account-access page.
- The `youtube` OAuth scope is sensitive. Until Google verifies the app, only test users can sign in.

## Project layout

```
Cadence/
  App/            Entry point, root/tab navigation, dependency container
  DesignSystem/   Spacing, radius, color, typography, motion tokens + shared components
  Models/         Track, Playlist, AppError, LoadState
  Services/       YouTube API client, Google OAuth (PKCE + Keychain), player bridge, SwiftData recents
  Features/       Onboarding, Home, Discover, Search, Playlists, Recents, Catalog (albums, artists), Player, Account
```
