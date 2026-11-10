set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Run PhinTechStoreKit's tests (headless)
test:
    swift test

# Regenerate PhinTechStore.xcodeproj from project.yml
gen:
    xcodegen generate --use-cache

# Build the macOS app
build: gen
    xcodebuild -project PhinTechStore.xcodeproj -scheme PhinTechStore build

# Build and launch the app
run: build
    open "$(xcodebuild -project PhinTechStore.xcodeproj -scheme PhinTechStore -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/PhinTechStore.app"

# Launch a Debug build in the background, listening on a socket for scripts/debug.py to drive (snapshots, menus),
# without taking focus; files are opened with it
[positional-arguments]
debug-app *files: build
    mkdir -p "$HOME/Library/Application Support/PhinTechStore"
    rm -f "$HOME/Library/Application Support/PhinTechStore/debug.sock"
    open -n -g --env DEBUG_SOCKET="$HOME/Library/Application Support/PhinTechStore/debug.sock" -a "$(xcodebuild -project PhinTechStore.xcodeproj -scheme PhinTechStore -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/PhinTechStore.app" "$@"
    scripts/debug.py ping >/dev/null && echo "PhinTechStore is listening; try: just debug snapshot out.png"

# Send a command to the Debug build started by debug-app (try: just debug help)
[positional-arguments]
debug *args:
    @scripts/debug.py "$@"

# Publish ad copy and per-app art (content/) to apps.phin.tech, where the store reads it: no store release needed
publish-content *args:
    tools/publish-content.py {{args}}

# Origin is Forgejo, which mirrors to GitHub, where .github/workflows/release.yml notarizes and publishes the tag.
# Write release-notes/<version>.md first (`just notes <part>`) for notes of your own.
# Cut a release for GitHub Actions to build: bump (patch, minor, major, beta), commit, tag v<version>, push
[positional-arguments]
cut part *args:
    test "$(git branch --show-current)" = main || { echo "cut from main"; exit 1; }
    git fetch --quiet origin main && test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || { echo "main is not origin/main; push or pull first"; exit 1; }
    {{release_tool}} bump "$@"
    version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml) && \
      git add -A && git commit --quiet -m "PhinTechStore $version" && git tag "v$version" && \
      git push --quiet --atomic origin main "v$version" && \
      echo "Pushed v$version; the build: https://github.com/phin-tech/phin-tech-store/actions/workflows/release.yml"

# Remove build artifacts and the generated Xcode project
clean:
    rm -rf .build DerivedData PhinTechStore.xcodeproj

# The release recipes (release-check, doctor, bump, ship and the rest): app-release, in release.just, which
# apple-template keeps up to date
import 'release.just'
