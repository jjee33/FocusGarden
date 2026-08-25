"""Writes latest.json, the file the in-app updater reads.

    python tools/make_manifest.py --version 0.2.0 --repo owner/name \
        --windows dist/FocusGarden-Setup-0.2.0.exe \
        --linux dist/FocusGarden-0.2.0-x86_64.AppImage \
        --notes-file notes.md --output latest.json

Published as a release asset, so it is reachable at the version-independent
URL .../releases/latest/download/latest.json. That URL is why this exists at all:
it always resolves to the newest release, needs no token, and has no rate limit
worth hitting -- unlike the GitHub API.

The SHA-256 of each asset is the part that matters. The app verifies a download
against it before handing the file to the operating system, so a manifest with a
wrong or missing digest must fail the release rather than ship.

See docs/UPDATES.md.
"""

import argparse
import hashlib
import json
import sys
from datetime import date
from pathlib import Path

# Release notes are shown in a toast and a dialog, not a browser. The full text
# lives on the release page, which notes_url points at.
NOTES_LIMIT = 400


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def summarise(notes: str) -> str:
    """The first paragraph, capped. Anything longer belongs on the release page."""
    paragraph = notes.strip().split("\n\n")[0].strip()
    paragraph = " ".join(paragraph.split())
    if len(paragraph) <= NOTES_LIMIT:
        return paragraph
    return paragraph[:NOTES_LIMIT].rsplit(" ", 1)[0] + "…"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--windows", type=Path)
    parser.add_argument("--linux", type=Path)
    parser.add_argument("--notes-file", type=Path)
    parser.add_argument("--output", type=Path, default=Path("latest.json"))
    args = parser.parse_args()

    version = args.version.lstrip("v")
    tag = f"v{version}"
    base = f"https://github.com/{args.repo}/releases/download/{tag}"

    platforms = {}
    for key, path in (("windows", args.windows), ("linux", args.linux)):
        if path is None:
            continue
        if not path.is_file():
            raise SystemExit(f"error: {path} does not exist")
        platforms[key] = {
            "url": f"{base}/{path.name}",
            "sha256": digest(path),
            "size": path.stat().st_size,
        }

    if not platforms:
        raise SystemExit("error: no platform assets given; the manifest would be useless")

    notes = ""
    if args.notes_file and args.notes_file.is_file():
        notes = summarise(args.notes_file.read_text(encoding="utf-8"))

    manifest = {
        "version": version,
        "released": date.today().isoformat(),
        "notes_url": f"https://github.com/{args.repo}/releases/tag/{tag}",
        "notes": notes,
        "platforms": platforms,
    }

    args.output.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(args.output.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
