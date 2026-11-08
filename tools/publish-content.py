#!/usr/bin/env python3
"""Publish the store's ad copy and per-app art to the download page, so the store shows a new or changed ad
without a new release of the store.

Reads content/ads.json, content/promo.json, content/store.json (the hotline) and content/art/, and uploads to the phin-apps R2 bucket (served at
https://apps.phin.tech): the pictures whose checksum changed go to _store/art/, the shop's own pictures and fonts (for
the download page, which app-release draws as the shop) to _store/site/, then _store/content.json, which lists the ads,
the first-visit promo and every file's SHA-256. The store app reads it on launch and on Reload and downloads only
pictures it doesn't have; app-release reads it when it draws the page, at the next release or `app-release page`.

content/listings.json is for what's on the shelves for its code alone, with nothing to download (a server): each entry
goes into the catalog, apps.json and private/apps.json, with no releases and a `source` the store's Get the Source
opens. app-release keeps entries it didn't write, so a listing stays when an app is released. Stores before 0.5 and the
download page skip an entry without releases. An entry that has releases belongs to app-release and is left alone.

Usage: tools/publish-content.py [--dry-run]
Needs the `cf` CLI signed in (`cf auth login`), as `just ship` does for the download page.
"""
from __future__ import annotations
import argparse, hashlib, json, shutil, subprocess, sys, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
BUCKET = "phin-apps"
PREFIX = "_store"
PUBLIC = "https://apps.phin.tech"
TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".otf": "font/otf"}
# The download page's own pictures and fonts: _store/site/<name> from these files in the repo.
SITE = {
    "wood-wall.jpg": ROOT / "App/Resources/Art/wood-wall.jpg",
    "store-front.jpg": ROOT / "App/Resources/Art/store-front.jpg",
    "pepper-mark.png": ROOT / "content/site/pepper-mark.png",
    **{f"fonts/EBGaramond-{w}.otf": ROOT / f"App/Resources/Fonts/EBGaramond-{w}.otf"
       for w in ("Regular", "Italic", "Bold", "ExtraBold")},
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remote_manifest() -> dict:
    # Cloudflare turns away Python's default User-Agent, so name this tool.
    req = urllib.request.Request(f"{PUBLIC}/{PREFIX}/content.json", headers={"User-Agent": "phin-tech-store-publish-content"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {"ads": {}, "art": {}}
        sys.exit(f"could not read the published content.json: {e}")


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


def cf_get(key: str) -> dict | None:
    """A JSON object in the bucket, or None when it isn't there."""
    r = subprocess.run(["cf", "r2", "objects", "get", key, "--text", "--bucket-name", BUCKET], capture_output=True, text=True)
    out = r.stdout + r.stderr
    if "10007" in out or "does not exist" in out:
        return None
    if r.returncode or "APIError" in out[:200]:
        sys.exit(f"could not read {key} from the bucket: {out.strip()[-300:]} (is cf logged in? `cf auth login`)")
    return json.loads(r.stdout)


LISTING_KEYS = ("title", "description", "category", "how", "source")


def publish_listings(listings: dict, dry: bool) -> None:
    """Puts each listing in the catalog: private/apps.json (what app-release reads and writes) first, then apps.json."""
    for key in ("private/apps.json", "apps.json"):
        catalog = cf_get(key)
        if catalog is None:
            print(f"  {key} isn't in the bucket; skipped")
            continue
        apps = catalog.setdefault("apps", {})
        changed = []
        for slug, listing in listings.items():
            missing = [k for k in ("title", "description", "category", "source") if not listing.get(k)]
            if missing:
                sys.exit(f"content/listings.json: {slug} needs {', '.join(missing)}")
            old = apps.get(slug)
            if old and old.get("releases"):
                print(f"  {slug} has releases in {key}, so app-release owns it; left alone")
                continue
            new = {**{k: listing[k] for k in LISTING_KEYS if listing.get(k)}, "releases": [], "locked": False,
                   "pinned": bool(listing.get("pinned"))}
            if old != new:
                apps[slug] = new
                changed.append(slug)
        if not changed:
            continue
        out = ROOT / "build" / key.replace("/", "-")
        out.parent.mkdir(exist_ok=True)
        out.write_text(json.dumps(catalog, indent=2, sort_keys=True))
        print(f"  {key}: {', '.join(changed)}")
        put(key, out, "application/json", dry)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true", help="say what would be uploaded, upload nothing")
    a = ap.parse_args()

    # Even a dry run reads the live catalog through cf, so say so up front instead of failing with a traceback.
    if shutil.which("cf") is None:
        sys.exit("publish-content: the Cloudflare CLI (cf) is not on PATH. Install it and run `cf auth login`; "
                 "`command -v cf` must find it in this shell (another shell, such as an agent's, can have a different PATH).")

    ads = json.loads((CONTENT / "ads.json").read_text())
    art = {}
    for path in sorted((CONTENT / "art").iterdir()):
        if path.suffix.lower() in TYPES:
            art[path.stem] = {"file": f"art/{path.name}", "sha256": sha256(path), "_path": path}

    site = {name: {"file": f"site/{name}", "sha256": sha256(path), "_path": path} for name, path in SITE.items()}
    store_path = CONTENT / "store.json"  # the shop's own details: the hotline and its page
    extra = json.loads(store_path.read_text()) if store_path.exists() else {}
    promo_path = CONTENT / "promo.json"
    promo = json.loads(promo_path.read_text()) if promo_path.exists() else None

    remote = remote_manifest()
    changed = [(n, f) for n, f in art.items() if remote.get("art", {}).get(n, {}).get("sha256") != f["sha256"]]
    changed += [(n, f) for n, f in site.items() if remote.get("site", {}).get(n, {}).get("sha256") != f["sha256"]]
    print(f"{len(ads)} ads, {len(art)} pictures, {len(site)} site files; {len(changed)} files new or changed")
    for _, f in changed:
        put(f"{PREFIX}/{f['file']}", f["_path"], TYPES[f["_path"].suffix.lower()], a.dry_run)

    strip = lambda files: {n: {"file": f["file"], "sha256": f["sha256"]} for n, f in files.items()}
    manifest = {**extra, "ads": ads, "art": strip(art), "site": strip(site)}
    if promo:
        manifest["promo"] = promo
    out = ROOT / "build" / "content.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False))
    # Last, so the manifest never names a picture that isn't up yet.
    put(f"{PREFIX}/content.json", out, "application/json", a.dry_run)
    listings_path = CONTENT / "listings.json"
    if listings_path.exists():
        publish_listings(json.loads(listings_path.read_text()), a.dry_run)
    if not a.dry_run:
        print(f"Published: {PUBLIC}/{PREFIX}/content.json")
        print("The download page shows it at the next release of any app, or now with `just release-tool page`.")


if __name__ == "__main__":
    main()
