#!/usr/bin/env python3
"""Generate one image through OpenRouter and save it as a PNG.

Usage: genimage.py OUT.png "prompt" [--model M] [--aspect 3:4] [--ref image.png ...]
The key comes from $OPENROUTER_API_KEY, or 1Password via `op read` if unset.
"""
import argparse, base64, json, os, subprocess, sys, urllib.request

OP_REF = "op://Private/w5vhn64v3mb4pqr4wvvemwbtlu/credential"

def key():
    k = os.environ.get("OPENROUTER_API_KEY")
    if k:
        return k
    try:
        return subprocess.run(["op", "read", OP_REF], check=True, capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        sys.exit("genimage: set OPENROUTER_API_KEY, or install the 1Password CLI (op) so the key can be read from 1Password.")
    except subprocess.CalledProcessError as e:
        sys.exit("genimage: could not read the OpenRouter key from 1Password:\n"
                 f"  {(e.stderr or '').strip() or 'op failed'}\n"
                 "Set OPENROUTER_API_KEY, or sign in (turn on the 1Password app's CLI integration, then `op signin`). "
                 "A shell that cannot reach the app, such as an agent's, fails this way even when your terminal works.")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("prompt")
    ap.add_argument("--model", default="google/gemini-3-pro-image")
    ap.add_argument("--aspect", default="3:4")
    ap.add_argument("--ref", action="append", default=[], help="a reference image to show the model (repeatable)")
    a = ap.parse_args()
    content = [{"type": "text", "text": a.prompt}]
    for ref in a.ref:
        mime = "image/png" if ref.lower().endswith(".png") else "image/jpeg"
        with open(ref, "rb") as f:
            content.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64," + base64.b64encode(f.read()).decode()}})
    body = {
        "model": a.model,
        "messages": [{"role": "user", "content": content}],
        "modalities": ["image", "text"],
        "image_config": {"aspect_ratio": a.aspect},
        "max_tokens": 4000,
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key()}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.load(r)
    try:
        url = resp["choices"][0]["message"]["images"][0]["image_url"]["url"]
    except (KeyError, IndexError):
        sys.exit("no image in response: " + json.dumps(resp)[:800])
    data = base64.b64decode(url.split(",", 1)[1])
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "wb") as f:
        f.write(data)
    print(a.out, len(data))

if __name__ == "__main__":
    main()
