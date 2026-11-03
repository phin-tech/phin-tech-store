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

# Remove build artifacts and the generated Xcode project
clean:
    rm -rf .build DerivedData PhinTechStore.xcodeproj

# The release recipes (release-check, doctor, bump, ship and the rest): app-release, in release.just, which
# apple-template keeps up to date
import 'release.just'
