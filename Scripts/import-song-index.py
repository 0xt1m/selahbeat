#!/usr/bin/env python3
"""Merge the Worship Song Index catalogue into server/catalog/seed-songs.json.

The site publishes the search index its own front end uses - title, artist,
recommended keys, tempo and meter for roughly three thousand songs - and its
robots.txt allows fetching it. Only the facts are taken: a tempo is not
authorship. These tempos come from a maintained song database rather than the
starter seed's guesses, so they are imported as verified.

Songs already in the seed file are never touched, so tempos you have corrected
survive re-running this.

    python3 Scripts/import-song-index.py            # merge and write
    python3 Scripts/import-song-index.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

SOURCE = "https://worshipsongindex.com/song-search.json"
USER_AGENT = "SelahBeat catalog import (https://selahbeat.com)"

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "server" / "catalog" / "seed-songs.json"

# What the app can actually play. A meter outside this is dropped rather than
# guessed at.
ALLOWED_NOTE_VALUES = {2, 4, 8, 16}
MIN_BPM, MAX_BPM = 20, 400

# Matches the app's MusicalKey spellings; anything else is imported without a
# key rather than with a wrong one.
KEY_PATTERN = re.compile(r"^[A-G](#|b)?m?$")


def fetch(url: str) -> list[dict]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def title_key(title: str) -> str:
    """A title stripped to its bones, for spotting the same song twice.

    "10,000 Reasons (Bless The Lord)" and "10,000 Reasons" are one song, and
    importing both would put two rows a drummer has to choose between into
    every search.
    """
    bare = re.sub(r"\([^)]*\)", " ", title.lower())
    return re.sub(r"[^a-z0-9]+", "", bare)


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:80]


def parse_meter(text: str) -> tuple[int, int] | None:
    match = re.match(r"^\s*(\d{1,2})\s*/\s*(\d{1,2})\s*$", text or "")
    if not match:
        return None
    beats, note_value = int(match.group(1)), int(match.group(2))
    if not (1 <= beats <= 32) or note_value not in ALLOWED_NOTE_VALUES:
        return None
    return beats, note_value


def normalise(entry: dict) -> dict | None:
    title = (entry.get("t") or "").strip()
    if not title:
        return None

    try:
        bpm = round(float(entry.get("b")))
    except (TypeError, ValueError):
        return None
    if not MIN_BPM <= bpm <= MAX_BPM:
        return None

    meter = parse_meter(entry.get("x") or "4/4")
    if meter is None:
        return None
    beats, note_value = meter

    # "m" and "f" are the keys the site recommends for male and female vocal
    # ranges; the male one is the closer stand-in for a band's usual key.
    key = (entry.get("m") or "").strip()
    if not KEY_PATTERN.match(key):
        key = ""

    song_id = (entry.get("s") or "").strip() or slugify(title)
    if not song_id:
        return None

    return {
        "id": song_id,
        "title": title,
        "artist": (entry.get("a") or "").strip() or None,
        "bpm": bpm,
        "beats": beats,
        "noteValue": note_value,
        "key": key or None,
        "notes": None,
        "revision": 1,
        # Sourced from a maintained index rather than estimated, so these do
        # not show up in the "needs a tempo check" list.
        "verified": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--source", default=SOURCE)
    parser.add_argument("--limit", type=int, default=0, help="import at most N new songs")
    args = parser.parse_args()

    seed = json.loads(SEED.read_text())
    existing = {song["id"] for song in seed["songs"]}
    # Titles too, since the same song often carries a different slug here and
    # there. Matched on the title alone: the songs already in the seed are
    # curated, and a second copy of one under another artist's name is noise.
    existing_titles = {title_key(song["title"]) for song in seed["songs"]}

    print(f"Fetching {args.source}")
    raw = fetch(args.source)
    print(f"  {len(raw)} songs in the index")

    added, skipped_existing, rejected = [], 0, 0
    seen: set[str] = set()
    for entry in raw:
        song = normalise(entry)
        if song is None:
            rejected += 1
            continue
        key = title_key(song["title"])
        # Within the import itself, two songs may share a title honestly - a
        # different "Holy" by a different artist is a different song - so those
        # are kept apart by artist.
        stamp = f"{key}|{(song['artist'] or '').lower()}"
        if song["id"] in existing or key in existing_titles or stamp in seen:
            skipped_existing += 1
            continue
        existing.add(song["id"])
        seen.add(stamp)
        added.append(song)
        if args.limit and len(added) >= args.limit:
            break

    print(f"  {len(added)} new, {skipped_existing} already known, {rejected} unusable")

    if args.dry_run:
        for song in added[:10]:
            print(f"    + {song['title']} - {song['artist']} - {song['bpm']} BPM")
        print("Dry run: nothing written.")
        return 0

    if not added:
        print("Nothing to add.")
        return 0

    seed["songs"].extend(added)
    seed["songs"].sort(key=lambda s: s["title"].lower())
    SEED.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(seed['songs'])} songs to {SEED.relative_to(ROOT)}")
    print("Now run: ./Scripts/sync-seed.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
