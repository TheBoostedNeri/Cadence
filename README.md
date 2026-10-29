# Cadence

A native SwiftUI music player for iOS 26+ and macOS 26+ that browses YouTube with the official
**YouTube Data API v3** and plays songs in YouTube's official **IFrame player**, with
Liquid Glass throughout. There are no third-party dependencies. An Android version, in Kotlin
and Jetpack Compose, lives in `android/`.

## Features

### 🎧 Listen
- **Home**: your liked music, playlists, new uploads from subscriptions, and Jump Back In
- **Discover**: what's trending, plus 22 genres to explore, from Pop to Jazz
- **Search**: songs and music videos, updating as you type
- **Albums and artists**: Go to Album or Go to Artist from any song, with artist pages like Apple Music's

### ▶️ Now Playing
- Full-bleed artwork that glides into a small header when you open lyrics or Up Next
- Time-synced lyrics, with controls that step aside while you read
- Up Next: drag to reorder, Shuffle, Repeat, and **Autoplay** with similar music
- Like a song with the ☆, AirPlay, and the system volume slider

### 📚 Library
- Your real YouTube playlists: create, rename, delete, add and remove songs
- Every song has a ⋯ menu: Play Next, Play Last, Add to Playlist, Go to Album or Artist, Share
- Pick several songs in Discover and add them to a playlist together
- Recently Played, kept separately for each service

### 💻 iPad and Mac
- **iPad**: sidebar, song grids, Now Playing beside the app, and keyboard shortcuts
- **Mac**: a native app laid out like Apple Music, with a glass player bar, a lyrics and Up Next panel, and a Playback menu

### 🔑 Quota at a glance
YouTube allows 10,000 API units a day per project. Browsing is cheap; these cost the most:

| Action | Units |
| --- | --- |
| Search, or finding the video for an album, artist or Discover song (once per song) | 100 |
| Add a song to a playlist, like a song, rename or delete a playlist | 50 |
| Load Trending, liked music or a page of a playlist | 1 |

Albums, artists and Discover's genres come from Apple's free iTunes catalog, which needs no key and uses no quota.

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

## Android

The Android app (Android 10 and later) has the same features as the iPhone app with YouTube: Home, Discover with genres, Search, albums and artists, your playlists, likes, Recently Played, Now Playing with synced lyrics and Up Next (Shuffle, Repeat, Autoplay), and the experimental background play, which shows a media notification and lock-screen controls. Apple Music isn't available on Android.

It uses only Google's AndroidX and Jetpack Compose libraries, and reads its settings from the same `Config/Secrets.xcconfig` as the iPhone app:

- `YOUTUBE_API_KEY`: requests name the iPhone app's bundle ID, so the key restricted to iOS apps works as it is.
- `GOOGLE_CLIENT_ID`: sign-in uses the iPhone app's OAuth client in a Chrome Custom Tab, and Google sends it back to the app through the client's reversed ID.
- `CADENCE_BUNDLE_IDENTIFIER`: sent with API requests, as above.

Open the `android` folder in Android Studio and press Run. Change `Config/Secrets.xcconfig`, then build again to pick up the new values.

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
android/          The Android app: the same layout under app/src/main/java/com/nerijus/cadence
```
