#!/usr/bin/env python3
"""Publish the store's ad copy and per-app art to the download page, so the store shows a new or changed ad
without a new release of the store.

Reads content/ads.json and content/art/, uploads to the phin-apps R2 bucket (served at https://apps.phin.tech):
the pictures whose checksum changed go to _store/art/, then _store/content.json, which lists the ads and every
picture's SHA-256. The store reads it on launch and on Reload, and downloads only pictures it doesn't have.

Usage: tools/publish-content.py [--dry-run]
Needs the `cf` CLI signed in (`cf auth login`), as `just ship` does for the download page.
"""
import argparse, hashlib, json, subprocess, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
BUCKET = "phin-apps"
PREFIX = "_store"
PUBLIC = "https://apps.phin.tech"
TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remote_manifest() -> dict:
    try:
        with urllib.request.urlopen(f"{PUBLIC}/{PREFIX}/content.json", timeout=30) as r:
            return json.load(r)
    except Exception:
        return {"ads": {}, "art": {}}


def put(key: str, path: Path, content_type: str, dry: bool) -> None:
    cmd = ["cf", "r2", "objects", "put", key, "--file", str(path), "--content-type", content_type,
           "--bucket-name", BUCKET]
    if dry:
        print("  would upload", key)
        return
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode or "APIError" in out[:400]:
        sys.exit(f"upload of {key} failed: {out.strip()[-300:]}")
    print("  uploaded", key)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true", help="say what would be uploaded, upload nothing")
    a = ap.parse_args()

    ads = json.loads((CONTENT / "ads.json").read_text())
    art = {}
    for path in sorted((CONTENT / "art").iterdir()):
        if path.suffix.lower() in TYPES:
            art[path.stem] = {"file": f"art/{path.name}", "sha256": sha256(path), "_path": path}

    old = remote_manifest().get("art", {})
    changed = [name for name, f in art.items() if old.get(name, {}).get("sha256") != f["sha256"]]
    print(f"{len(ads)} ads, {len(art)} pictures; {len(changed)} pictures new or changed")
    for name in changed:
        f = art[name]
        put(f"{PREFIX}/{f['file']}", f["_path"], TYPES[f["_path"].suffix.lower()], a.dry_run)

    manifest = {"ads": ads, "art": {n: {"file": f["file"], "sha256": f["sha256"]} for n, f in art.items()}}
    out = ROOT / "build" / "content.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False))
    # Last, so the manifest never names a picture that isn't up yet.
    put(f"{PREFIX}/content.json", out, "application/json", a.dry_run)
    if not a.dry_run:
        print(f"Published: {PUBLIC}/{PREFIX}/content.json")


if __name__ == "__main__":
    main()
