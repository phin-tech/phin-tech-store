#!/usr/bin/env python3
"""Generate every image in art/prompts.json that is missing from art/raw, in parallel,
then write a resized JPEG of each into App/Resources/Art.

Usage: tools/genart.py [name ...]   (names force a regenerate of just those)
"""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art", "raw")
OUT = os.path.join(ROOT, "App", "Resources", "Art")

def run(img, styles, force):
    raw = os.path.join(RAW, img["name"] + ".png")
    if force or not os.path.exists(raw):
        prompt = styles[img["style"]] + img["prompt"]
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "genimage.py"), raw, prompt,
                            "--aspect", img["aspect"]], capture_output=True, text=True)
        if r.returncode:
            return f"FAIL {img['name']}: {r.stderr.strip()[-400:]}"
    jpg = os.path.join(OUT, img["name"] + ".jpg")
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "82", "-Z", "1600", raw, "--out", jpg],
                   check=True, capture_output=True)
    return f"ok {img['name']}"

def main():
    spec = json.load(open(os.path.join(ROOT, "art", "prompts.json")))
    os.makedirs(RAW, exist_ok=True); os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    imgs = [i for i in spec["images"] if not only or i["name"] in only]
    if os.environ.get("OPENROUTER_API_KEY") is None:
        sys.path.insert(0, os.path.join(ROOT, "tools"))
        import genimage
        os.environ["OPENROUTER_API_KEY"] = genimage.key()
    with ThreadPoolExecutor(6) as ex:
        for line in ex.map(lambda i: run(i, spec["styles"], bool(only)), imgs):
            print(line, flush=True)

if __name__ == "__main__":
    main()
