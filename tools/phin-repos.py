#!/usr/bin/env python3
"""Chores across every Phin Tech project that publishes to apps.phin.tech.

    tools/phin-repos.py list                       the projects it finds, their app-release pin and state
    tools/phin-repos.py pull [--dry-run]           fast-forward each checkout's main from its remote
    tools/phin-repos.py bump-app-release v1.10.1 [--dry-run] [--bender]
                                                   move every project to that app-release tag

A project is a git checkout under ~/src/github.com/phin-tech (or --root) whose release.toml publishes to the download
page (a [downloads] table, or `downloads = ...` in an [[apps]] table). Worktrees named like `repo.branch` are skipped.

`pull` never merges or touches uncommitted work. On main it runs `git pull --ff-only`; on another branch it moves
the local main ref forward without checking it out. Anything that can't fast-forward is left alone, and listed.

`bump-app-release` matters because a release redraws the whole download page with the app-release it runs: one project
on an old tag puts the old page back for every app. For each project it makes a temporary worktree of the remote main,
changes the tag in scripts/release/pyproject.toml, refreshes uv.lock, runs `app-release check`, commits only those two
files, pushes, and removes the worktree. Your checkouts and their uncommitted work are not touched; `pull` afterwards
brings the commit down. --bender commits and pushes git.phin.tech projects as the bender agent account (through the
forgejo-bender SSH alias and ~/.config/bender/env), as an agent must; without it, everything goes as you.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_ROOT = Path.home() / "src/github.com/phin-tech"
PIN = re.compile(r'(app-release = \{ git = "https://git\.phin\.tech/sam/app-release", )(?:tag|branch|rev) = "[^"]*"( \})')
FORGEJO = re.compile(r"(?:https://git\.phin\.tech/|git@git\.phin\.tech:|forgejo-bender:)([^/]+/[^/]+?)(?:\.git)?/?$")
CO_AUTHOR = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"


def git(repo: Path, *args: str, check: bool = True, env: dict | None = None) -> str:
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, env=env)
    if check and r.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {(r.stderr or r.stdout).strip()}")
    return r.stdout.strip()


def publishes(text: str) -> bool:
    return bool(re.search(r"^\[(?:apps\.)?downloads\]", text, re.M) or re.search(r"^downloads\s*=", text, re.M))


def repo_name(url: str) -> str:
    """The repository's name in a remote or source URL, lowercased: github.com/phin-tech/Foo.git and
    forgejo-bender:sam/foo both give foo."""
    return re.sub(r"\.git$", "", url.rstrip("/")).rsplit("/", 1)[-1].rsplit(":", 1)[-1].lower()


def fetch_main(repo: Path) -> bool:
    """Brings origin/main up to date; a remote that is slow or unreachable is skipped, not fatal."""
    if not remote(repo):
        return False
    try:
        r = subprocess.run(["git", "-C", str(repo), "fetch", "-q", "origin", "main"], capture_output=True, text=True,
                           timeout=45)
    except subprocess.TimeoutExpired:
        print(f"note  {repo.name}: fetching its remote timed out; using what was fetched before", file=sys.stderr)
        return False
    return r.returncode == 0


def catalog_sources() -> set[str]:
    """The repositories named as `source` on the download page, by name: a project whose checkout doesn't have its
    release.toml yet (it was committed from another clone) is still found."""
    import json
    import urllib.request
    req = urllib.request.Request("https://apps.phin.tech/apps.json", headers={"User-Agent": "phin-repos"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            apps = json.load(r).get("apps", {})
    except Exception as e:
        print(f"note  couldn't read the download page's apps.json ({e}); finding projects by release.toml only",
              file=sys.stderr)
        return set()
    return {repo_name(a["source"]) for a in apps.values() if isinstance(a.get("source"), str)}


def projects(root: Path) -> list[Path]:
    """Every checkout that publishes to the download page: its release.toml says so (in the working tree, or on the
    remote's main, which may be newer), found from the checkouts with a release.toml and those named as a source on
    the page. One checkout per repository, preferring the one named like it."""
    sources = catalog_sources()
    candidates = [d for d in sorted(root.iterdir(), key=lambda p: p.name.lower())
                  if "." not in d.name and (d / ".git").exists()
                  and ((d / "release.toml").is_file() or (remote(d) and repo_name(remote(d)) in sources))]
    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        list(pool.map(fetch_main, candidates))
    found: dict[str, Path] = {}
    for d in candidates:
        local = (d / "release.toml").read_text() if (d / "release.toml").is_file() else ""
        upstream = git(d, "show", "origin/main:release.toml", check=False) if remote(d) else ""
        if not (publishes(local) or publishes(upstream)):
            continue
        name = repo_name(remote(d)) if remote(d) else f"local:{d}"
        if name not in found or d.name.lower() == name:
            found[name] = d
    return sorted(found.values(), key=lambda p: p.name.lower())


def pin_in(text: str) -> str | None:
    m = re.search(r'app-release = \{[^}]*(tag|branch|rev) = "([^"]*)"', text)
    return f"{m.group(1)} {m.group(2)}" if m else None


def pin_of(repo: Path, ref: str | None = None) -> str:
    """The app-release pin in the working tree, or at `ref` (like origin/main)."""
    rel = "scripts/release/pyproject.toml"
    text = git(repo, "show", f"{ref}:{rel}", check=False) if ref else ((repo / rel).read_text() if (repo / rel).is_file() else "")
    if not text:
        return "none (runs from an app-release checkout)"
    return pin_in(text) or "(unreadable)"


def remote(repo: Path) -> str:
    return git(repo, "remote", "get-url", "origin", check=False)


def push_target(repo: Path, bender: bool) -> str:
    url = remote(repo)
    if bender and (m := FORGEJO.match(url)):
        return f"forgejo-bender:{m.group(1)}.git"
    return "origin"


def state(repo: Path) -> str:
    branch = git(repo, "branch", "--show-current", check=False) or "(detached)"
    dirty = len([l for l in git(repo, "status", "--porcelain", check=False).splitlines() if l])
    return f"on {branch}" + (f", {dirty} uncommitted" if dirty else "")


# ---- list

def cmd_list(args) -> int:
    print(f"{'project':30} {'app-release on remote main':30} {'in your checkout':22} checkout")
    for repo in projects(args.root):
        upstream = pin_of(repo, "origin/main") if remote(repo) else "(no remote)"
        local = pin_of(repo)
        print(f"{repo.name:30} {upstream:30} {(local if local != upstream else 'same'):22} {state(repo)}")
    return 0


# ---- pull

def cmd_pull(args) -> int:
    problems = []
    for repo in projects(args.root):
        name = repo.name
        if not remote(repo):
            print(f"skip  {name}: no remote")
            continue
        behind = git(repo, "rev-list", "--count", "main..origin/main", check=False) or "?"
        ahead = git(repo, "rev-list", "--count", "origin/main..main", check=False) or "?"
        if behind == "0":
            print(f"ok    {name}: up to date")
            continue
        if ahead not in ("0", "?"):
            problems.append(f"{name}: main has {ahead} commit(s) of its own and is {behind} behind; merge or rebase it yourself")
            continue
        branch = git(repo, "branch", "--show-current", check=False)
        if args.dry_run:
            print(f"would {name}: fast-forward main by {behind} commit(s) ({state(repo)})")
            continue
        try:
            if branch == "main":
                git(repo, "pull", "-q", "--ff-only", "origin", "main")
            else:
                git(repo, "fetch", "-q", "origin", "main:main")
            print(f"ok    {name}: main moved forward {behind} commit(s) ({state(repo)})")
        except RuntimeError as e:
            problems.append(f"{name}: couldn't fast-forward ({e}); your uncommitted changes may touch the same files")
    for p in problems:
        print(f"left  {p}")
    return 1 if problems else 0


# ---- bump-app-release

def bender_env() -> dict:
    env = dict(os.environ)
    path = Path.home() / ".config/bender/env"
    token = None
    for line in path.read_text().splitlines() if path.is_file() else []:
        if line.startswith("FORGEJO_TOKEN="):
            token = line.split("=", 1)[1].strip().strip('"').strip("'")
    if token:
        # uv fetches app-release from git.phin.tech with git's credentials: bender's, not the maintainer's.
        env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://git.phin.tech/.extraheader",
                   GIT_CONFIG_VALUE_0=f"Authorization: token {token}")
    return env


def cmd_bump(args) -> int:
    tag = args.tag
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        print(f"{tag} isn't a tag like v1.10.1", file=sys.stderr)
        return 2
    env = bender_env() if args.bender else dict(os.environ)
    failed = []
    for repo in projects(args.root):
        name = repo.name
        pyproject_rel = "scripts/release/pyproject.toml"
        if not git(repo, "show", f"origin/main:{pyproject_rel}", check=False):
            print(f"skip  {name}: no scripts/release on its main (it runs from an app-release checkout)")
            continue
        target = push_target(repo, args.bender)
        on_forgejo = target.startswith("forgejo-bender:")
        ident = ["-c", "user.name=bender", "-c", "user.email=bender@noreply.phin.tech"] if on_forgejo else []
        work = Path(tempfile.mkdtemp(prefix=f"phin-bump-{name}-")) / "repo"
        try:
            git(repo, "fetch", "-q", target, "main")
            git(repo, "worktree", "add", "-q", "--detach", str(work), "FETCH_HEAD")
            pyproject = work / pyproject_rel
            text = pyproject.read_text()
            new_text, n = PIN.subn(rf'\g<1>tag = "{tag}"\g<2>', text)
            if n != 1:
                raise RuntimeError("couldn't find the app-release line in scripts/release/pyproject.toml")
            if new_text == text:
                print(f"ok    {name}: already on {tag}")
                continue
            if args.dry_run:
                print(f"would {name}: {pin_of(repo)} -> tag {tag}, check, commit and push to {target}")
                continue
            pyproject.write_text(new_text)
            for cmd in (["uv", "lock", "-q", "--upgrade-package", "app-release", "--project", "scripts/release"],
                        ["uv", "run", "--quiet", "--project", "scripts/release", "app-release", "check"]):
                r = subprocess.run(cmd, cwd=work, capture_output=True, text=True, env=env)
                if r.returncode:
                    raise RuntimeError(f"{' '.join(cmd[:2])} failed: {(r.stderr or r.stdout).strip()[-300:]}")
            git(work, "add", pyproject_rel, "scripts/release/uv.lock")
            message = (f"Use app-release {tag}\n\nA release redraws the whole download page with the app-release it runs, "
                       f"so every project that publishes there moves to the newest tag together.\n\n{CO_AUTHOR}")
            git(work, *ident, "commit", "-q", "-m", message, env=env)
            git(work, "push", "-q", target, "HEAD:main", env=env)
            print(f"ok    {name}: {tag}, {git(work, 'log', '--oneline', '-1')[:9]} pushed to {target}")
        except RuntimeError as e:
            failed.append(name)
            print(f"FAIL  {name}: {e}")
        finally:
            git(repo, "worktree", "remove", "--force", str(work), check=False)
    if failed:
        print(f"\n{len(failed)} failed: {', '.join(failed)}. Nothing was pushed for them.")
    elif not args.dry_run:
        print(f"\nAll on {tag}. Run `{Path(sys.argv[0]).name} pull` to bring the commits into your checkouts.")
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0], epilog=__doc__.split("\n\n", 1)[1],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT, help=f"where the checkouts are (default {DEFAULT_ROOT})")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="the projects, their app-release pin and state").set_defaults(func=cmd_list)
    p = sub.add_parser("pull", help="fast-forward each checkout's main")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_pull)
    b = sub.add_parser("bump-app-release", help="move every project to an app-release tag")
    b.add_argument("tag")
    b.add_argument("--dry-run", action="store_true")
    b.add_argument("--bender", action="store_true", help="commit and push git.phin.tech projects as bender")
    b.set_defaults(func=cmd_bump)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
