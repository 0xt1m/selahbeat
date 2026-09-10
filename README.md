# SelahBeat

A metronome for worship drummers. macOS now, iOS next.

The whole design turns on one requirement: **the click has to start the instant
you press start**, so that stopping and restarting mid-song doesn't throw the
band off. Measured on an M-series Mac, the first click lands **2–4 ms** after
the press.

## Status

| | |
|---|---|
| macOS app | Builds and runs. 4 MB. |
| iOS app | Builds for simulator. Needs an Apple Development certificate for device. |
| Core tests | 37 passing, including sample-accurate scheduling over a simulated 10 minutes. |
| Server | Builds and runs; API, admin site and landing page all verified. |
| Auto-update | In-app "new version" banner works now. Sparkle one-click install is one script away — see below. |

## Quick start

```bash
./Scripts/bootstrap.sh                  # installs xcodegen, generates the project
swift test                              # 37 core tests, no Xcode needed
./.build/debug/AudioCheck               # end-to-end check against real audio hardware
open SelahBeat.xcodeproj                # run the SelahBeat-macOS scheme
```

`AudioCheck` is worth running first — it prints the actual sample rate, buffer
size and measured start latency on your machine:

```
engine running     : true
sample rate        : 44100 Hz
buffer size        : 256 frames
est. start latency : 5.80 ms
first tick after Start: 2.48 ms
peak render time   : 6 µs
render load        : 0.10%
```

## How the instant start works

The audio graph is created and started **when the app launches and is never
stopped**. It renders continuously — zeros when idle — and never reports
silence, so CoreAudio never powers the output chain down between songs.

Pressing Start therefore costs two atomic stores. It does not pay for
`AVAudioEngine.start()`, which can take 5–80 ms. The first tick fires at sample
offset 0 of the very next hardware callback.

All beat timing lives in a C render callback as a sample-frame counter, never a
timer. `Timer`/`DispatchSourceTimer` jitter by 5–50 ms, quantise every onset to
a buffer boundary, and drift against the audio device's real clock. The
scheduler computes each tick as `epochFrame + tickIndex * framesPerTick`,
recomputed rather than accumulated, so drift cannot grow with time — verified by
a test that runs a simulated ten minutes and asserts every one of ~1,200 onsets
lands on its exact expected frame.

The render callback never allocates, locks, or touches the Swift runtime. The
Swift render block contains no logic at all; it calls one C function.

## App icon

Generated, not hand-drawn, so it tracks the palette:

```bash
swift Scripts/GenerateAppIcon.swift
```

It renders a metronome — tapered body with the pendulum and weight knocked out
— and emits every size Xcode needs into both asset catalogs. Two details that
matter: sizes at or below 64px use bolder, larger proportions, because the
full-size rod width lands under one pixel at 16px and disappears; and the
pendulum's lean is capped so its rounded tip stays inside the tapering sides
rather than being clipped by the body edge.

## Adaptive layout

One shell, chosen by available width:

| Width | Layout |
|---|---|
| Regular (Mac, iPad) | Sidebar + detail, full-width transport bar, two-column Metronome screen |
| Compact (iPhone) | Tab bar, compact transport pinned above it, single-column Metronome |

The transport bar drops controls by priority as the window narrows — meter at
800pt, subdivision at 900, sound picker at 1000, the loaded-song label at 1220 —
so it never overflows. Transport, tempo and tap are always present. Beat dots in
the transport show one dot per counted beat rather than per tick, because a
tick-level row grows without bound (7/8 in sixteenths is 28 dots).

## Layout

```
Sources/
  SelahBeatAudioC/     C — the only real-time-critical code
  SelahBeatCore/       models, store, engine wrapper, catalog, updates
  SelahBeatUI/         SwiftUI shared by both apps
  AudioCheck/          hardware verification tool
Apps/macOS/ Apps/iOS/  thin @main + the four files that differ per platform
Tests/                 swift-testing suites
server/                Next.js app: API + admin + landing page
Scripts/               bootstrap, enable-sparkle, sync-seed
```

Cross-platform code lives in a SwiftPM package so `swift test` runs the entire
core — including the render scheduler — from the command line with no Xcode, no
simulator and no signing.

`SelahBeat.xcodeproj` is **generated and gitignored**. Edit `project.yml` and
run `xcodegen generate`; never hand-edit the project file.

## Data model notes

- **Order is array order.** No `order: Int` field to drift out of sync; maps 1:1
  onto SwiftUI's `.onMove`.
- **`ServiceItem.id` is not `songID`.** The same song can appear twice in one
  service, and rows need stable drag identity.
- **Key and tempo overrides live on the placement, not the song.** The key your
  team plays this week isn't the song's key.
- **Keys keep their spelling.** `Bb`, never `A#` — a chart says Bb.
- Storage is plain `Codable` JSON with atomic writes and a `.bak` generation.
  2,000 songs is ~500 KB; a linear scan beats a database round trip and lets
  search run synchronously on every keystroke.

## Server

See [`server/README.md`](server/README.md). Short version:

```bash
cd server && npm install
cp .env.example .env.local     # set ADMIN_PASSWORD and SESSION_SECRET
npm run seed                   # loads the 76-song starter catalog
npm run dev                    # http://localhost:3000
```

The app mirrors the catalog locally and delta-syncs, so **song lookup works
offline too** — which matters, because church wifi tends to fail exactly when
someone needs it.

⚠️ The seeded tempos are **estimates** and are flagged `verified: false`. The
admin site shows how many still need checking against a recording.

## Enabling Sparkle auto-update

```bash
./Scripts/enable-sparkle.sh
```

Sparkle ships disabled because resolving a remote SwiftPM package needs network
access a sandboxed shell may not have — and when it can't, `xcodebuild` hangs at
"Resolve Package Graph" with no error rather than failing. The app is fully
functional without it and still tells you when a release exists; Sparkle
upgrades that to one-click install.

## Releasing

See [RELEASING.md](RELEASING.md) for the full sequence. Short version, once the
one-time setup is done:

```bash
git tag -a v1.0.0 -m "SelahBeat 1.0.0" && git push origin v1.0.0
```

## Before the first release

1. Export the Developer ID certificate **with its private key** as `.p12`,
   base64 it, and store it as the `MACOS_CERT_P12_BASE64` secret.
2. Create an App Store Connect API key (`.p8`, downloadable once) for
   notarisation → `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
3. Generate the Sparkle EdDSA keypair and **back up the private key** — losing
   it means no installed copy can ever update again. Public key goes in
   `Apps/macOS/Info.plist` as `SUPublicEDKey`.
4. Push a `v*` tag; `.github/workflows/release.yml` builds, signs, notarises,
   staples, builds a DMG, signs the appcast and publishes the release.

`SUFeedURL` points at GitHub Releases, so the update channel works before the
server exists. Point it at your domain later if you want the control.

iOS device builds are now possible — an *Apple Development: Tymofii Matviiv
(M6GX3CF932)* certificate is present alongside the Developer ID one. iOS still
has no release workflow; it would go through App Store Connect, not Sparkle.

## Screenshots

Verify iOS yourself without a device:

```bash
xcrun simctl boot "iPhone 16"
xcodebuild -project SelahBeat.xcodeproj -scheme SelahBeat-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath build/DerivedDataIOS CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted build/DerivedDataIOS/Build/Products/Debug-iphonesimulator/SelahBeat.app
xcrun simctl launch booted app.selahbeat.SelahBeat -seed-sample-data
xcrun simctl io booted screenshot shot.png
```

`-seed-sample-data` (DEBUG builds only, and only when the library is empty)
creates two sample services so the tile grids have something in them.
`-tab-services` / `-tab-library` open straight to a tab.

## Known gaps

- Sparkle is disabled by default (see above).
- Count-in is in settings but not yet wired to the engine.
- The macOS Metronome screen shows Start in both the main view and the
  persistent transport bar. Harmless, but redundant.
- iPad screenshots via `simctl` come out rotated, and the orientation flips
  between captures. Rotate with `sips -r 90` (or 270) to read them.
- No first-run onboarding content, so both tile grids start empty.
- iOS is simulator-verified only; lock-screen transport controls
  (`MPRemoteCommandCenter`) are not implemented and would be the highest-value
  iOS addition for stop/start mid-song.
