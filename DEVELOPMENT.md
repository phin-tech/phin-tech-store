# Developing PhinTechStore

## How the store works

- **The catalog** is `https://apps.phin.tech/apps.json`, the download page's manifest, which app-release writes when
  any app is released there. `CatalogLoader` (in `PhinTechStoreKit`) groups it into a shelf per category and keeps the
  last copy in `~/Library/Application Support/Phin Tech Store/` for offline launches. A new release of any app shows up
  without a release of the store.
- **Installing** (`App/Model/Installer.swift`) downloads `<key>/<file>` from the page, checks the SHA-256 the
  catalog lists, unpacks it with `ditto`, and moves the `.app` into `/Applications` (or `~/Applications`), sending an
  older copy to the Trash. A Herdr plugin's zip goes to Downloads instead. The installed version is read from
  the app's `Info.plist` each time, not with `Bundle(url:)`, which caches per path and would keep reporting the old
  version after an update.
- **Ads and art** come from `_store/content.json` on the page (see below), with `content/` as built into the app as the
  fallback. `StoreContent` fetches the manifest on launch and on ⌘R, and downloads only pictures whose checksum it
  doesn't have.
- **Menus** that depend on state (Store, View) are small views (`StoreMenuItems`, `ViewMenuItems`) observing the
  models. Plain command closures don't redraw when the models change.
- **Updates**: Sparkle checks once a day and installs without asking (`SUAutomaticallyUpdate`). Settings turns that
  off.

## Building

Needs Xcode 26.6 or later, [xcodegen](https://github.com/yonaskolb/XcodeGen), [just](https://just.systems)
and, for releasing, [uv](https://docs.astral.sh/uv/), `gh` and the 1Password CLI `op`:
`brew install xcodegen just uv gh 1password-cli`.

```sh
just build           # generate the Xcode project and build the app
just run             # build and launch it
just test            # PhinTechStoreKit's tests, headless
just release-check   # release.toml and the version files make sense
```

`PhinTechStore.xcodeproj` is generated from `project.yml` and gitignored, so change settings there, not in Xcode. The
same goes for the Info.plists and entitlements in `Generated/` (also gitignored), which xcodegen writes from
`project.yml`'s `info` and `entitlements` properties.

**Signing.** Builds are signed to run locally unless a gitignored `Signing.local.xcconfig` sets `DEVELOPMENT_TEAM`
and `CODE_SIGN_IDENTITY = Apple Development` (see `Signing.xcconfig`). Set the team there rather than in Xcode's
Signing & Capabilities pane, which is lost when the project is regenerated.

**Looking at the running app.** `just debug-app` builds and launches a Debug copy in the background, listening on
`~/Library/Application Support/PhinTechStore/debug.sock`; `just debug <command>` drives it with `scripts/debug.py`.
`just debug snapshot out.png` renders the front window to a PNG (the app draws it itself, so no screen-recording
permission is needed), `just debug windows` lists the windows, `just debug menu File "New Window"` chooses a menu item,
and `just debug quit` quits it. `just debug help` lists the rest. The driver (`App/DebugDriver.swift`) is only
compiled into Debug builds and only listens when the app is launched with `DEBUG_SOCKET` set.

## Releasing

**One command:** `just ship patch` (or `minor`, `major`, `beta`). It bumps the version (`just bump`), commits and
pushes to `main`, builds the app headless, signs it with the Developer ID Application certificate, notarizes it with
Apple and staples the ticket (`just notarize`), then publishes the GitHub release, its Sparkle appcast (`just release`). Write `release-notes/<next version>.md` first for curated notes: `just notes patch` (or `minor`, `beta --of patch`, …) drafts it with a cheap model on OpenRouter from the commits since the last release, to read and edit. It must run on a Mac
with the certificate in its keychain, from a clean, pushed `main`. Every release recipe takes `--dry-run`, which runs
the checks and reads but only prints what it would change: `just ship beta --dry-run`.

**Betas.** `just ship beta` makes the next beta: from 0.6.1, `0.7.0-beta.1`, then `-beta.2`. For a beta of a
patch or a major instead, `just ship beta --of patch` (0.6.1 → `0.6.2-beta.1`) or `--of major` (`1.0.0-beta.1`);
later betas carry on with plain `just ship beta`, and `just ship patch` releases it. A beta is a GitHub
pre-release, so GitHub's "latest", the download link stay on the last release. Its appcast entry
is added to the latest release's appcast in Sparkle's `beta` channel, which only copies with Settings › Updates › Get
beta versions turned on take (on by default in a beta build). A later `just ship minor` (or `patch`) releases the
beta's version, `0.7.0`, and beta testers move on to it, since the build number only goes up. A beta needs a release
to join, so the first thing shipped must be a release.

**The tooling** is [app-release](https://git.phin.tech/sam/app-release), shared with Dottie and every app made from
the same template: a Python program pinned to a tag in `scripts/release/pyproject.toml` and run with uv, which fetches it
with your git credentials for git.phin.tech. What it knows about PhinTechStore is in `release.toml`. Versions are written
by [bump-my-version](https://github.com/callowayproject/bump-my-version) (`.bumpversion.toml` lists the files), and
the appcast by Sparkle's own `generate_appcast`. Settings come from the environment (`NOTARY_OP_ITEM`,
`DEVELOPMENT_TEAM`, `NOTARY_PROFILE`), so a build machine can run it unattended; `op` works there with a 1Password
service account (`OP_SERVICE_ACCOUNT_TOKEN`). `just doctor` checks everything it needs outside the repository.

Credentials come from 1Password (`op://Development/lc6wrq7lltjd47uue26cdxttzu`: `apple_id`, `team_id`, `app_specific_password`, `p12` and
`p12_passphrase` (the Developer ID certificate), and `sparkle_private_key`), so a Mac needs only the 1Password CLI signed in (`op signin`) to release. The certificate
goes into a keychain made for each run and deleted afterwards; without `p12` in the item, the login keychain's is used.
To keep the secrets in Infisical, or in a CI tool's environment, instead, add `[secrets]` to `release.toml` (see
app-release's README). Without any notarization credentials, `just notarize` falls
back to a notarytool keychain profile: `xcrun notarytool store-credentials phin-tech-store-notary --apple-id <apple id>
--team-id J35P7AJDN7`.

The steps by hand, if one fails halfway:

1. `just bump patch`, commit and push.
2. `just notarize` (or in Xcode: Product ▸ Archive, then Distribute App ▸ Direct Distribution). It leaves the app in
   `build/release/<version>/export/PhinTechStore.app`. Run again, it redoes only the stages (archive, export,
   notarize) whose inputs changed, so a rejected or interrupted notarization doesn't archive again; `--verbose` shows
   xcodebuild's full output.
3. `just release` (or `just release <path to PhinTechStore.app>`; with no argument it takes the newest notarized app):
   checks it is a stapled, notarized Developer ID build of the version in `project.yml` and that `main` is clean and
   pushed, then publishes `PhinTechStore-<version>.zip` as a GitHub release tagged `v<version>`. Then it makes the
   appcast (`just appcast` redoes that).

## Updates

The app updates itself in place with [Sparkle](https://sparkle-project.org) (`App/UpdateChecker.swift`). Its feed,
`SUFeedURL`, is `releases/latest/download/appcast.xml`: an asset of the newest release (GitHub skips drafts and
pre-releases), made by Sparkle's `generate_appcast` in `just appcast`. Entries are signed with the EdDSA key in
1Password (`sparkle_private_key`, given to the tool on stdin; the public half is `SUPublicEDKey` in `project.yml`), so
installed copies only accept updates signed by it. Do not lose or replace that key: copies already out there would
reject every later update. `just appcast` checks every entry is signed and the new one verifies before it uploads.
Sparkle's tools are downloaded, pinned, into `~/Library/Caches/app-release`. Debug builds do not check for updates.

## Content and the download page

`content/` is the store's own content, and also the source of what apps.phin.tech shows:

| Path | What |
| --- | --- |
| `content/ads.json` | Each app's ad, keyed as in `apps.json` (`PhinTechStore`, `Dottie`, `herdr-phin-util`): `layout`, `boxColor`, `headline`, `kicker`, `sections`, `tagline`, `finePrint`, and `title` for a name other than the catalog's |
| `content/art/<key>-box.jpg`, `<key>-hero.jpg` | The box cover (3:4) and the ad's picture |
| `content/promo.json` | The app offered in the first-visit dialog and on the seal on the page's sign (this store) |
| `content/store.json` | The hotline number and its page, for the sign, the ads' fine print and Help |
| `content/site/` | Pictures for the page only (Pepper's mark); the wall and shop front come from `App/Resources/Art` |

`just publish-content` uploads whatever changed to `_store/` on the page (with `cf`, as `just ship` does) and then
`_store/content.json`, which lists it all with checksums. Installed stores show it the next time they open. The
page shows it at the next release of any app that publishes there, or now with `just release-tool page`. A new
app's ad needs no release of the store.

**New art.** Add `<key>-box` and `<key>-hero` prompts to `art/prompts.json`, then run
`tools/genart.py <key>-box <key>-hero`. It calls an image model on OpenRouter (`tools/genimage.py`; the key is read
from 1Password, `op://Private/w5vhn64v3mb4pqr4wvvemwbtlu/credential`, unless `OPENROUTER_API_KEY` is set) and writes
JPEGs into `content/art`. `--ref` gives the model a reference picture. Use the Pepper art in
`../jeo-paw-dy/brand/pepper-head.png` for anything with Pepper in it: Pepper is a cream mutt with floppy ears, and the
right one is orange with a brown patch. The key has its own spending cap on OpenRouter; a `402 Payment Required` means
that cap is used up, even when the account has credit.

**The page's design** lives in [app-release](https://git.phin.tech/sam/app-release) (`page.py`), not here. Every
release redraws the whole page with the app-release it runs. So this repo and every project that publishes to the page
stay on the newest app-release tag, or an older one puts the old page back.

`tools/phin-repos.py` does the chores across every project that publishes to the page. It finds them from the
checkouts under `~/src/github.com/phin-tech` with a `release.toml`, and from the sources on the page.

- `list` shows each project's app-release pin on its remote and in your checkout.
- `pull` fast-forwards each checkout's `main` and never touches uncommitted work.
- `bump-app-release v1.10.1` moves them all to a tag. It makes each change in a temporary worktree, then checks,
  commits and pushes it; add `--bender` when an agent runs it. Every command takes `--dry-run`.

## First release

Once, before the first `just ship`:

1. `just bootstrap`: creates the GitHub repository `phin-tech/phin-tech-store` (public: Sparkle and Homebrew download the
   release zips without credentials), pushes `main` to it, and runs `just doctor`, which checks `gh`,
   every 1Password field and the Developer ID certificate.
2. Fix whatever `just doctor` lists, and run it again until it is clean.
3. The Sparkle key in `op://Development/lc6wrq7lltjd47uue26cdxttzu` must be the other half of `SUPublicEDKey` in `project.yml` (`just appcast` checks
   this before uploading anything). For a key of its own, run Sparkle's `generate_keys -x <file>` from
   `~/Library/Caches/app-release/sparkle/*/bin`, put the private key in a new item, and switch to it with
   `uvx copier update --defaults -d op_item=<item> -d sparkle_public_key=<public key>`.
4. `Signing.local.xcconfig` (gitignored) with `DEVELOPMENT_TEAM = J35P7AJDN7` and
   `CODE_SIGN_IDENTITY = Apple Development`. Without it, the development build `just ship` installs in
   `/Applications` is signed ad hoc while Sparkle inside it has the team's signature, and it crashes at launch
   ("different Team IDs"). The notarized release is fine either way.

Then `just ship minor --dry-run`, and if that reads right, `just ship minor`.
