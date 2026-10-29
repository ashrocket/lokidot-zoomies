#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications"
BIN_DIR="$HOME/.local/bin"
SOURCE_APP=""
BUILD=1
usage() { echo 'Usage: ./lokidot install [--app-dir FOLDER] [--bin-dir FOLDER] [--no-build] [--from APP]'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-dir|--bin-dir|--from)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      case "$1" in
        --app-dir) APP_DIR="$2" ;;
        --bin-dir) BIN_DIR="$2" ;;
        --from) SOURCE_APP="$2"; BUILD=0 ;;
      esac
      shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
if [[ $BUILD == 1 ]]; then "$ROOT/scripts/build.sh"; fi
if [[ -z "$SOURCE_APP" ]]; then SOURCE_APP="$(cat "$ROOT/dist/app-path.txt")"; fi
[[ -d "$SOURCE_APP" && ! -L "$SOURCE_APP" && -x "$SOURCE_APP/Contents/MacOS/lokidot" ]] || { echo 'Build LokiDot first, then install it.' >&2; exit 1; }
SOURCE_APP="$(cd "$SOURCE_APP" && pwd)"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
[[ "$IDENTIFIER" == com.ashrocket.LokiDotZoomies || "$IDENTIFIER" == com.ashrocket.LokiDotZoomies.pet.* ]] || { echo 'This is not a LokiDot app.' >&2; exit 1; }
codesign --verify --strict "$SOURCE_APP"
mkdir -p "$APP_DIR" "$BIN_DIR"
APP_DIR="$(cd "$APP_DIR" && pwd)"; BIN_DIR="$(cd "$BIN_DIR" && pwd)"
DESTINATION="$APP_DIR/$(basename "$SOURCE_APP")"
LAUNCHER="$BIN_DIR/lokidot"
if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
  [[ -d "$DESTINATION" && ! -L "$DESTINATION" ]] || { echo 'The app destination is not an ordinary app folder; nothing was replaced.' >&2; exit 1; }
  OLD_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$OLD_ID" == "$IDENTIFIER" ]] || { echo 'A different app occupies the destination; nothing was replaced.' >&2; exit 1; }
fi
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
  [[ -L "$LAUNCHER" && "$(readlink "$LAUNCHER")" == "$DESTINATION/Contents/MacOS/lokidot" ]] || { echo 'A different lokidot command already exists; choose another --bin-dir.' >&2; exit 1; }
fi
if [[ "$SOURCE_APP" != "$DESTINATION" ]]; then
  STAGE="$(mktemp -d "$APP_DIR/.lokidot-install.XXXXXX")"
  COMMITTED=0
  finish() {
    if [[ $COMMITTED == 0 && -d "$STAGE/previous.app" && ! -e "$DESTINATION" ]]; then mv "$STAGE/previous.app" "$DESTINATION"; fi
    rm -rf "$STAGE"
  }
  trap finish EXIT
  ditto "$SOURCE_APP" "$STAGE/new.app"
  codesign --verify --strict "$STAGE/new.app"
  # Ask this app to close normally. Never force-stop an app during an update.
  "$SOURCE_APP/Contents/MacOS/lokidot" quit
  if [[ -d "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGE/previous.app"; fi
  mv "$STAGE/new.app" "$DESTINATION"
  COMMITTED=1
fi
if [[ ! -L "$LAUNCHER" ]]; then ln -s "$DESTINATION/Contents/MacOS/lokidot" "$LAUNCHER"; fi
printf '\nInstalled %s\nCommand: %s\n\n' "$DESTINATION" "$LAUNCHER"
printf 'Open the app in Finder, or run: lokidot\nTry: lokidot all circle\n'
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) printf '\nFor this terminal, add the launcher to PATH:\nexport PATH="%s:$PATH"\n' "$BIN_DIR" ;;
esac
