---
name: publish-to-phin-store
description: Publish a new app (Mac app, Cargo Mac app, Herdr plugin or Herdr mod) to apps.phin.tech and the Phin Tech Store, or give an already published app its store ad and art. Use when asked to release, ship or publish an app to the store or download page, set up a project's release tooling, or add an app's ad.
---

# Publishing an app to the Phin Tech Store

Three repos, checked out under `~/src/github.com/phin-tech/`:

| Repo | Role |
| --- | --- |
| `apple-template` | copier template. Creates a new app, or adds only the release tooling to an existing project |
| `app-release` | The release tool (`just ship`, `notarize`, `release`, ...) and the code that draws apps.phin.tech (`page.py`) |
| `phin-tech-store` | The store app, and `content/` (ads, art): the shop's look for each app |

Publishing has two independent halves. The first puts the app on the download page, and so in the store. The second gives
it a real ad. An app with no ad still appears, with a plain box and an ad made from its description.

Read `README.md` in app-release for every `release.toml` key, and `MIGRATING.md` in apple-template before moving an
existing project. This skill is the route through them, not a copy.

## Rules

- A release redraws the whole page with the app-release tag the project pins. Pin the **newest** tag. An older tag puts
  the old page back for every app. Check with `tools/phin-repos.py list` in phin-tech-store.
- The maintainer runs `just ship`. Do the setup, run `--dry-run`, and stop unless asked to ship.
- `just publish-content` changes what every installed store and apps.phin.tech show. Run `--dry-run` first and publish
  only when asked.
- Never lose or replace the Sparkle private key: installed copies would reject every later update. `SUPublicEDKey` in
  `project.yml` must match `sparkle_private_key` in the secrets store.
- git.phin.tech needs credentials over HTTPS. On this machine use SSH through the `forgejo-luigi` alias
  (`git clone forgejo-luigi:sam/<repo>.git`). uv fetches app-release over HTTPS, so it needs a credential helper or token.
  An agent uses bender's token (`~/.config/bender/env`) via `GIT_CONFIG_COUNT` and
  `http.https://git.phin.tech/.extraheader`, never the maintainer's.

## 1. Pick the kind

What the app is decides its `release.toml`. Examples are in app-release's README, "The kinds of app".

| App | `release.toml` |
| --- | --- |
| Mac app, public | `repo = "phin-tech/<app>"`, `[homebrew]`, `[downloads]` |
| Mac app, code on Forgejo | `releases = "phin-tech/releases"` instead of `repo` |
| Mac app for a few people | `[bucket]` (Sparkle feed under a random prefix: `app-release new-prefix <name>`) |
| Mac app for your own Macs | `[install] hosts = [...]` |
| Rust Mac app, no Xcode | `kind = "cargo-app"`, `[cargo]` |
| Herdr plugin (Go) | `kind = "herdr-plugin"`, `[herdr]`, `[downloads]` required |
| Herdr app mod (JavaScript) | `kind = "herdr-mod"`, `[mods]`, `[downloads]` |

`[downloads]` is what puts the app on apps.phin.tech and in the store. Without it the app is not published there. Its
keys are all optional: `category`, `description`, `source`, `how`, `pin`, `allow` (private apps, via Cloudflare Access).
Betas stay off the page.

## 2. Set up the project

**New Mac app.** From the apple-template checkout:

```sh
cp .env.example .env        # once; fill in team id, op item, Sparkle public key, bundle prefix, GitHub owner, tap
just new ~/src/<app> -d app_name=<App>
cd ~/src/<app> && git init -b main && just build && just test && just release-check
just bootstrap              # creates the public GitHub repo and runs `just doctor`
```

**Existing project, release tooling only.** `just new <project> -d scope=release` from the template checkout (or
`uvx copier copy <template> .` in the project). Then add `import 'release.just'` to its justfile, run
`uv lock --project scripts/release`, `just release-check` and `just ship patch --dry-run`. The project must have
xcodegen, a quoted `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml`, and (with Sparkle) an
`exactVersion` pin. See MIGRATING.md.

**Herdr plugin or mod.** Hand-write `release.toml` as above. The plugin's `build.sh` should copy `dist/<binary>-<os>-<arch>`
into place before trying Go, so the zip installs without Go. For a mod, `[mods] names` must each have a folder with a
versioned `mod.json`, all agreeing.

Then, in the project:

- `just doctor` and fix what it lists (`op`, `gh`, `cf` signed in, certificate, every secret field). Repeat until clean.
- Check `scripts/release/pyproject.toml` pins the newest app-release tag (`git -C ~/src/github.com/phin-tech/app-release tag`).
- Write `release-notes/<next version>.md`, or draft it with `just notes patch` and edit it.
- `just ship patch --dry-run` (or `minor`). Read it. The maintainer then runs the real `just ship`, which bumps, commits,
  pushes, notarizes, publishes, uploads the zip to the bucket, and rewrites `apps.json` and the page.

The app's key on the page is its slug or app name (`Dottie`, `herdr-phin-util`). It is the `apps.json` id and the
anchor `apps.phin.tech/#<key>`. Use that key everywhere below.

## 3. Give it an ad (optional, no store release needed)

In `phin-tech-store`, after the app's first release appears in `https://apps.phin.tech/apps.json`:

1. **Copy.** Add `<key>` to `content/ads.json`: `layout` (`classic`, `photo`, `columns`, `product`), `boxColor` (`#rrggbb`),
   `headline`, `kicker`, `sections` (`heading`?, `body`), `tagline`, `finePrint`, optional `title`. Copy an existing
   entry's voice (Dottie's is a good model): 1980s magazine-ad tone, with a joke in the fine print.
2. **Art.** Add `<key>-hero` and `<key>-box` entries to `art/prompts.json` (`style`: `hero` or `box`, `aspect`, `prompt`).
   Run `tools/genart.py <key>-hero <key>-box`. It writes `content/art/<key>-box.jpg` (3:4 cover) and `<key>-hero.jpg`.
   The OpenRouter key is read from 1Password (or `OPENROUTER_API_KEY`). It has its own spending cap: a `402` means the cap
   is used, even with credit. For anything with Pepper the dog, pass `--ref ../jeo-paw-dy/brand/pepper-head.png`.
   Pepper is a cream mutt with floppy ears; the right one is orange with a brown patch. Look at the images before moving on.
3. **Check.** `just test`, then `just publish-content --dry-run`.
4. **Publish** only when asked: `just publish-content`. It uploads changed art to `_store/` and then `_store/content.json`.
   Stores pick it up on next open or View ▸ Reload the Shelves (⌘R). The page shows it at the next release of any app,
   or now with `just release-tool page`.

The same step edits `content/promo.json` (the first-visit offer) and `content/store.json` (the hotline), if asked.

## 4. Verify

- `https://apps.phin.tech/apps.json` lists the app with the new version and a checksum.
- `https://apps.phin.tech/#<key>` opens its ad.
- The store (`just run` in phin-tech-store, ⌘R) shows the box, and Install works.

## Gotchas

- Cloudflare in front of apps.phin.tech returns 403 to Python's default User-Agent. Send your own.
- Xcode's build service sometimes hangs at 0% CPU. Give `xcodebuild` and `just build` a timeout.
- A private app (`allow = [...]`) is listed only on `apps.phin.tech/private`, behind Access. Leave the bucket's `r2.dev`
  address off or the files can be fetched around Access.
- Cargo apps with Sparkle can't have an allow list, since Sparkle can't get past Access.
- Moving every project to a new app-release tag: `tools/phin-repos.py bump-app-release <tag> [--dry-run] [--bender]`
  in phin-tech-store.
