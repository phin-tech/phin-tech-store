---
name: publish-to-phin-store
description: Publish a new Phin Tech app (Mac app, Cargo Mac app, Herdr plugin or Herdr mod) to apps.phin.tech and the Phin Tech Store, or give an already published app its store ad and art. Use when asked to release, ship or publish an app to the store or download page, set up a project's release tooling for apps.phin.tech, add an app's ad, or move projects to a new app-release tag.
---

# Publishing an app to the Phin Tech Store

Three repos, checked out under `~/src/github.com/phin-tech/`:

| Repo | Role |
| --- | --- |
| `apple-template` | copier template. Creates a new app, or adds only the release tooling to an existing project |
| `app-release` | The release tool (`just ship`, `notarize`, `release`, ...): puts the zip, the manifest and the docs in the bucket |
| `apps-site` | Draws apps.phin.tech and docs.phin.tech from the bucket; a release, `publish-content` and `release-tool page` run its deploy |
| `phin-tech-store` | The store app, and `content/` (ads, art): the shop's look for each app |

Publishing has two independent halves. The first puts the app on the download page, and so in the store. The second gives
it a real ad. An app with no ad still appears, with a plain box and an ad made from its description.

Read `README.md` in app-release for the kinds of app (every `release.toml` key is in `src/app_release/config.py`), and `MIGRATING.md` in apple-template before moving an
existing project. This skill is the route through them, not a copy.

## Rules

- Pin the **newest** app-release tag. A release only writes data (apps-site draws the pages), but a pin before v1.11.0
  still draws the old page itself and puts it back for every app, and rejects `[site]`. Find it with `git -C ~/src/github.com/phin-tech/app-release fetch --tags -q &&
  git -C ~/src/github.com/phin-tech/app-release tag --sort=-v:refname | head -1` (plain `git tag` sorts as text and
  lists `v1.9.x` last). `tools/phin-repos.py list` in phin-tech-store shows every project's pin.
- To move a project to a tag: change `tag` in `scripts/release/pyproject.toml`, then
  `uv lock --upgrade-package app-release --project scripts/release`. **apple-template ships an old pin** (v1.9.1 at
  v0.4.1), so every project made from it needs this straight after creation.
- The maintainer runs `just ship`. Do the setup, run `--dry-run`, and stop unless asked to ship.
- `just publish-content` and `just release-tool page` change what every installed store and apps.phin.tech show
  (`page` runs apps-site's deploy). Run
  `publish-content --dry-run` first and publish only when asked. `publish-content` sends everything in `content/`,
  including unrelated uncommitted edits, plus `_store/site/*` and any `content/listings.json` entries (merged into the
  live `apps.json` and `private/apps.json`): check `git status` and the dry-run's file list.
- Never lose or replace the Sparkle private key: installed copies would reject every later update. `SUPublicEDKey` in
  `project.yml` must match `sparkle_private_key` in the secrets store.
- git.phin.tech needs credentials over HTTPS. The maintainer's machine reaches it over SSH through the `forgejo-luigi`
  alias (`git clone forgejo-luigi:sam/<repo>.git`). uv fetches app-release over HTTPS, so it needs a credential helper
  or token. An agent uses bender's identity, never the maintainer's: the `forgejo-bender` SSH alias, and bender's token
  (`~/.config/bender/env`, where it exists) through `GIT_CONFIG_COUNT` and
  `http.https://git.phin.tech/.extraheader`. `phin-repos.py --bender` does this. If neither is set up, stop and ask.

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

`[downloads]` is what puts the app on apps.phin.tech and in the store. Without it the app is not published there, and it
is required for Herdr plugins and mods. Its keys are all optional: `category`, `description`, `source`, `how`, `pin`, `allow` (private apps, via Cloudflare Access).
Betas stay off the page. Sparkle updates can't get past Access, so an app with `allow` needs its feed in `repo` or
`[bucket]` (app-release refuses the combination otherwise).

## 2. Set up the project

**New Mac app.** From the apple-template checkout:

```sh
cp -n .env.example .env     # once; fill in team id, op item, Sparkle public key, bundle prefix, GitHub owner, tap
just new ~/src/<app> -d app_name=<App> -d description="<one line>"   # copier asks every question .env doesn't answer;
                                                                       # add --defaults, or -d for each, to avoid the prompts
cd ~/src/<app> && git init -b main
# bump the app-release pin NOW (see Rules): the template's is old
just build && just test && just release-check
just bootstrap              # creates the public GitHub repo and runs `just doctor`
```

**Existing project, release tooling only.** `just new <project> -d scope=release` from the template checkout (or
`uvx copier copy <template> .` in the project). **Answer `-d downloads=true`**: it defaults to yes only for a whole new
app, so with `scope=release` the app silently stays off apps.phin.tech. The same goes for `github_releases`, `bucket`,
`install_on_macs`, `devices`: say which destinations you want. Then add `import 'release.just'` to its justfile, run
`uv lock --project scripts/release`, `just release-check` and `just ship patch --dry-run`. The project must have
xcodegen, a quoted `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml`, and (with Sparkle) an
`exactVersion` pin. See MIGRATING.md.

**Answers that matter for an existing project.** Pass `-d bundle_id=<exactly as in project.yml>`: the default is
`<prefix>.<slug>` with the slug lowercased, so `tech.phin.Cubicle` would become `tech.phin.cubicle` and `release.toml`
would disagree with the app. Also `-d homebrew_tap=…`, `-d macos_min=…`, `-d team_id=…`, `-d op_item=…`, `-d app_store=false`
unless it really is on the App Store, and, if the app embeds a command-line tool, `-d cli_binary=<its file name in
Contents/Helpers>` so the cask links it onto the PATH (`cli_binary` arrived after template v0.4.1; with an older template
add `binary = { path = "Contents/Helpers/<tool>", name = "<tool>" }` under `[homebrew]` by hand). `just new` reads `.env`
in the template checkout; with none, `ENV_FILE=/dev/null just new <project> --defaults -d …` takes every answer from the
command line (it prints a harmless "no /dev/null" line). Add `--pretend` first to see which files it would create.

**An existing SwiftPM app (no Xcode project).** app-release builds with Xcode, so the app needs a `project.yml` (xcodegen)
that builds the same sources; `Package.swift` can stay the source of truth for `swift test`. What worked for Cubicle:

- In `Package.swift`, add `.library(...)` products for the targets the app links (a C core, a shared library). An
  executable target cannot be linked from Xcode, but a library product can.
- `project.yml`: `packages: <Name>: path: .`; the app target compiles the app's source folder directly (`sources:`) and
  depends on those products. A command-line tool is its own `type: tool` target, embedded with
  `copy: { destination: wrapper, subpath: Contents/Helpers }` and `codeSign: true`.
- Put the tool in `Contents/Helpers`, not `Contents/MacOS`: on a case-insensitive disk `cubicle` and an app executable
  named `Cubicle` are the same file. Name the tool's target differently (`CubicleCLI`, with `PRODUCT_NAME: cubicle`) so
  their build folders do not collide either.
- `ENABLE_HARDENED_RUNTIME: YES`; `SWIFT_VERSION` matching the package (tools-version 5.9 is Swift 5 mode); a quoted
  `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- If the SwiftPM build should keep working without Sparkle, guard its code with `#if canImport(Sparkle)` and give a no-op
  stand-in, since `Package.swift` does not list it.
- Delete the old build script and any CI that used it. Anything the script put in the bundle (an icon, a zipped helper)
  needs a build phase that runs before signing: `Resources/` listed under `sources:` for plain files, or a
  `postBuildScripts` entry with declared `inputFiles` and `outputFiles` for generated ones.

**Herdr plugin or mod.** Not made by the template. Hand-write `release.toml` as above, and give the repo
`scripts/release/pyproject.toml` (copy apple-template's `template/scripts/release/pyproject.toml.jinja`, pinned to the
newest tag) with `uv lock --project scripts/release`, and the recipes (`release.just`, imported from the justfile).
Copy these from an existing plugin or mod repo (`herdr-phin-util`, `herdr-phin-picker`) if one is at hand; the
template's don't fit. `notes`, `notarize`, `testflight`, betas and build numbers don't apply to them. The plugin's `build.sh` should copy `dist/<binary>-<os>-<arch>`
into place before trying Go, so the zip installs without Go. For a mod, `[mods] names` must each have a folder with a
versioned `mod.json`, all agreeing.

Then, in the project:

- `just doctor` and fix what it lists (`op`, `gh`, `cf` signed in, certificate, every secret field). Repeat until clean.
- Check `scripts/release/pyproject.toml` pins the newest app-release tag (see Rules) and the lock file agrees.
- For Xcode and Cargo apps, write `release-notes/<next version>.md`, or draft it with `just notes patch` and edit it.
- `ship` bumps before it releases, so a new project at 0.1.0 would first ship as 0.1.1 or 0.2.0. To release exactly 0.1.0,
  set `MARKETING_VERSION` to `"0.0.0"` first, then `just ship minor`.
- `just ship patch --dry-run` (or `minor`). Read it. The maintainer then runs the real `just ship`, which bumps, commits,
  pushes, notarizes, publishes, uploads the zip to the bucket, and rewrites `apps.json` and the page.

The app's key is its `slug` in `release.toml`, which defaults to the app name without spaces (`Dottie`,
`herdr-phin-util`). It is the `apps.json` id and the anchor `apps.phin.tech/#<key>`. It is not copier's lowercased
`app_slug`. Use the key everywhere below.

## Before a repo goes public

Making a repo public cannot be undone: it can be cloned and cached before you make it private again. Ask first, then:

- Scan the whole history, not just the tree: `git log --all -p | grep -nE '(gho_|ghp_|github_pat_|AKIA|xox[bp]-|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20,}|op://|password)'`.
  An `op://` reference is an item path, not a secret, but `release.toml` and `.copier-answers.yml` carry one, so know that.
- List the authors (`git log --all --format='%an <%ae>' | sort | uniq -c`): commit emails are public, and a placeholder
  such as `none@none.com` may not be what you want in the history.
- If the code is derived from someone else's, keep their LICENSE notice and credit them in the README and the release notes.
- Remove inherited CI. A fork's workflows run on every push to a public repo; Cubicle's inherited "Nightly Build" failed on each one.
- `Signing.local.xcconfig`, `.env` and the like must be gitignored.
- Create the repo under `phin-tech` from the start, or transfer it (`gh api -X POST repos/<owner>/<repo>/transfer -f new_owner=phin-tech -f new_name=<name>`):
  the Sparkle feed URL is baked into every copy that ships.

## The app icon (separate from the store art)

The box and hero are for the store. The app icon is what people see in the Dock, in Finder and in the menu bar. For Cubicle
it was made like this, and it matched the store's look:

1. Brief an image tool (Codex's built-in image generator worked; `genart.py` is only for store art). Put the brief and two or
   three of the store's `-box.jpg` pictures, as style references, in an empty folder, and ask for: a 1024×1024 RGBA PNG in the
   standard macOS icon shape (a rounded squircle about 824 px across, transparent corners, a soft shadow); one bold motif that
   still reads at 32 px; no text, letters or numbers; a 512 px copy if there is an Alfred workflow; and a 72 px single-colour
   black glyph on transparent for a menu bar template image. Tell it to work only in that folder.
2. Look at every file before using it, including shrunk to 64 and 32 px, and check the corners really are transparent.
3. Build the `.icns` from the 1024 master with `sips -z` for each size and `iconutil -c icns`, in a script so it can be
   redone, and make sure the build puts it in the bundle (`CFBundleIconFile`, or the asset catalog).
4. Generated art has its own terms: check they suit shipping the app, and say how it was made in the repo.

## 3. Give it an ad (optional, no store release needed)

In `phin-tech-store`, after the app's first release appears in `https://apps.phin.tech/apps.json`:

1. **Copy.** Add `<key>` to `content/ads.json`: `layout` (`classic`, `photo`, `columns`, `product`), `boxColor` (`#rrggbb`),
   `headline`, `kicker`, `sections` (`heading`?, `body`), `tagline`, `finePrint`, optional `title`. Copy an existing
   Write it to `content/COPY.md`: the house voice, what each field holds, and each layout's shape.
2. **Art.** Add two objects to the `images` array in `art/prompts.json`:
   `{"name": "<key>-box", "style": "box", "aspect": "3:4", "prompt": "..."}` and the same for `<key>-hero` with
   `"style": "hero"` at the aspect `content/COPY.md` gives its layout (the ad crops it to that). `styles` supplies the shared look, so the
   prompt describes only the subject. Run `tools/genart.py <key>-box <key>-hero`: it generates `art/raw/<name>.png`
   through OpenRouter and writes `content/art/<key>-box.jpg` and `<key>-hero.jpg`. The OpenRouter key is read from
   1Password (or `OPENROUTER_API_KEY`). It has its own spending cap: a `402` means the cap is used, even with credit.
   `genart.py` takes no `--ref`. For anything with Pepper the dog, make the raw PNG first with
   `tools/genimage.py art/raw/<name>.png "<style text + prompt>" --aspect <a> --ref <pepper-head.png>`
   (the reference is `brand/pepper-head.png` in the jeo-paw-dy repo, if it is checked out; ask where it is if not),
   then run `tools/genart.py` with no names: it skips images whose raw PNG exists and only converts them. Pepper is a
   cream mutt with floppy ears; the right one is orange with a brown patch. Look at the images before moving on.
   A code-only entry with no download (a server, say) goes on the shelves through `content/listings.json` instead.
3. **Check.** `just test`, then `just publish-content --dry-run`.
4. **Publish** only when asked: `just publish-content`. It uploads changed art to `_store/` and then `_store/content.json`.
   Stores pick it up on next open or View ▸ Reload the Shelves (⌘R). It then runs apps-site's deploy, and
   apps.phin.tech shows it a minute or two later.

The same step edits `content/promo.json` (the first-visit offer) and `content/store.json` (the hotline), if asked.

The art can come later: an ad published without it (Cubicle's was) is fine, because apps-site draws the hero only if it
exists and an app with no box art gets the plain box.

## 4. Verify

- `https://apps.phin.tech/apps.json` lists the app with the new version and a checksum.
- `https://apps.phin.tech/<key>/index.html` opens its ad. Its docs page and gallery come from `[site]` in its
  `release.toml`: see the `apps-phin-tech` skill.
- The store shows the box and Install works: `just debug-app`, then `just debug snapshot out.png` (or a normal build
  and ⌘R). Don't quit the maintainer's own running copy. `snapshot` comes out blank for the shelves and ads; use
  `screencapture -o -l <window id>` for those.

## Gotchas

- Cloudflare in front of apps.phin.tech returns 403 to Python's default User-Agent. Send your own.
- Xcode's build service sometimes hangs at 0% CPU. Give `xcodebuild` and `just build` a timeout.
- A private app (`allow = [...]`) is listed only on `apps.phin.tech/private`, behind Access. Leave the bucket's `r2.dev`
  address off or the files can be fetched around Access.
- Moving every project to a new app-release tag: `tools/phin-repos.py bump-app-release <tag> [--dry-run] [--bender]`
  in phin-tech-store.
- An agent's shell may not reach 1Password. There, `op` says "No accounts configured" or "not currently signed in", and
  `ls ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t` says "Operation not permitted", while the same commands work
  in the maintainer's own terminal (herdr). Upgrading `op` and turning on the app integration did not change it. Before
  starting, ask for `op whoami` and `cf --version` run in the maintainer's terminal, and have them run the steps that need
  1Password or Cloudflare (`genart.py`, `publish-content`, `doctor`, `notarize`, `ship`) there. Prepare everything else.
- `cf` may not be on an agent's PATH: here it was `~/.node_modules/bin/cf` (an npm global), which the maintainer's shell
  finds and an agent's did not. Check `command -v cf` in both.
- The bender identity needs its host to resolve and its key and token on the machine. If `git ls-remote forgejo-bender:…`
  cannot connect and `~/.config/bender/env` is missing, an agent cannot push to Forgejo: commit to a branch in the local
  checkout and ask the maintainer to push it as themselves. Never use `forgejo-luigi`.
