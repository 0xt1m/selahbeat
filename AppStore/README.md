# App Store submission kit

Everything App Store Connect asks for, ready to paste. Screenshots are in
`screenshots/` at the exact pixel sizes Apple requires.

> **Blocker:** the Support and Privacy URLs below must be publicly reachable
> before you can submit. They exist as pages in the Next.js site (`/support`,
> `/privacy`) but the server is not deployed yet. Either deploy to EC2 first,
> or temporarily host those two pages somewhere public and use those URLs.

---

## App information

| Field | Value |
|---|---|
| Name (max 30) | `SelahBeat` |
| Subtitle (max 30) | `Metronome for worship teams` |
| Primary category | Music |
| Secondary category | Productivity |
| Bundle ID | `app.selahbeat.SelahBeat` |
| SKU | `selahbeat-001` |
| Copyright | `2026 Tymofii Matviiv` |
| Support URL | `https://selahbeat.com/support` |
| Marketing URL | `https://selahbeat.com` |
| Privacy Policy URL | `https://selahbeat.com/privacy` |

---

## Promotional text (max 170)

```
The click starts the instant you press start — so stopping and restarting
mid-song never throws the band off.
```

---

## Description

```
SelahBeat is a metronome built for one job: keeping a worship team together,
on a stage, under pressure.

INSTANT START
Most metronome apps take a moment to spin up their audio before the first
click. On stage that moment is the difference between the band locking in and
the band guessing. SelahBeat keeps its audio engine running from the second you
open the app, so pressing start costs nothing — the first click lands in a few
milliseconds, every time. Stop in the middle of a song and start again, and
nobody has to wait for you.

BUILD YOUR SERVICE
Group songs into a service, drag them into the order you're playing them, and
set the key your team is using this week. Step from song to song without
leaving the screen you're on — tempo, meter and key load into the transport
instantly. Next week, duplicate the service and change what moved.

EVERY SONG YOU'VE USED, REMEMBERED
Any song you add is saved. Start typing and it comes straight back, with the
tempo you set last time. Create your own songs with whatever tempo and meter
your arrangement actually uses.

LOOK UP A TEMPO YOU DON'T KNOW
Search a catalog of worship songs with their tempos, meters and keys. The
catalog is downloaded to your device, so it keeps working when the church wifi
doesn't.

WORKS WITH NO SIGNAL
The metronome, your services and every saved song work completely offline. No
account, no sign-in, nothing to set up.

TAP THE TEMPO
Tap along and it locks on. A fumbled tap gets rejected instead of wrecking the
estimate.

EVERY METER
4/4, 3/4, 6/8 felt in two, 12/8, 5/4, 7/8 grouped 2+2+3 — plus quarter, eighth,
triplet and sixteenth subdivisions. Accent, soften or mute any individual beat
by tapping it.

SIX CLICK SOUNDS
Beep, woodblock, cowbell, stick, rim, and a soft pulse that won't wear your
ears out across a ninety-minute service.

STAGE MODE
Full screen, near black, with the song, key and tempo big enough to read from
behind the kit.

HONEST ABOUT LATENCY
Bluetooth headphones add 150–300ms of delay that no app can remove. SelahBeat
detects a Bluetooth route and tells you, instead of letting you find out during
the first chorus.

NO ACCOUNT, NO TRACKING, NO ADS
SelahBeat collects nothing. Your services and songs live on your device and are
never uploaded.
```

---

## Keywords (max 100 characters)

```
drummer,tempo,bpm,click,setlist,praise,church,band,drums,rehearsal,timing,tap,practice,song
```

91 characters. Deliberately excludes "metronome" and "worship" — those are
already in the name and subtitle, which Apple indexes separately, so repeating
them wastes the budget.

---

## Age rating

Answer **None** to every question. Result: **4+**.

There is no user-generated content, no web browsing, no gambling, no contests
and no unrestricted web access.

---

## App Privacy questionnaire

Select **"No, we do not collect data from this app."**

This is truthful: there is no account system, no analytics SDK, no advertising
identifier and no crash reporting. The catalog sync is a one-way download whose
request carries only the app version and the usual network metadata; nothing is
stored against a user. If you later add accounts or analytics, this answer must
change before that build ships.

---

## Screenshots

| Folder | Device | Pixels | App Store slot |
|---|---|---|---|
| `screenshots/iphone-6.9/` | iPhone 16 Pro Max | 1320 × 2868 | iPhone 6.9" Display |
| `screenshots/iphone-6.5/` | iPhone 11 Pro Max | 1242 × 2688 | iPhone 6.5" Display |
| `screenshots/ipad-13/` | iPad Pro 13-inch (M4) | 2064 × 2752 | iPad 13" Display |

Three per device: metronome, services, library.

App Store Connect shows a separate upload well per display size and each accepts
only its own exact dimensions, so all three sets are needed while the app
supports iPhone and iPad.

The 6.5" set needs a simulator that Xcode does not install by default:

```bash
xcrun simctl create "SelahBeat-6.5" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-18-6
```

Regenerate any set with:

```bash
xcrun simctl launch booted app.selahbeat.SelahBeat \
  -seed-sample-data -disable-update-check -tab-services
xcrun simctl io booted screenshot out.png
```

`-seed-sample-data`, `-tab-services`, `-tab-library` and `-disable-update-check`
are DEBUG-only launch arguments, compiled out of release builds.
`-disable-update-check` matters: without it the app finds the published release
and draws an "update available" banner across the top of every screenshot.

---

## Submission order

1. Register the bundle ID at developer.apple.com → Identifiers
2. Create the app record at appstoreconnect.apple.com → Apps → **+**
3. Create an **Apple Distribution** certificate (you currently have Developer ID
   and Apple Development only)
4. Deploy the site so the Support and Privacy URLs resolve
5. Upload a build (TestFlight first)
6. Paste the metadata above, upload screenshots, answer the two questionnaires
7. Submit for review — typically 1–3 days
