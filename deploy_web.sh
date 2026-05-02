#!/usr/bin/env bash
set -Eeuo pipefail

DEST_DIR="/var/www/v3_portal"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
USE_SUDO_RSYNC="${USE_SUDO_RSYNC:-1}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

command -v "$FLUTTER_BIN" >/dev/null 2>&1 || die "flutter not found"
command -v rsync >/dev/null 2>&1 || die "rsync not found"

[ -d "$DEST_DIR" ] || die "Destination directory does not exist: $DEST_DIR"
[ -f "pubspec.yaml" ] || die "pubspec.yaml not found"

APP_VERSION="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
[ -n "$APP_VERSION" ] || die "Could not read version from pubspec.yaml"

BUILD_STAMP="$(date -u +%Y%m%d%H%M%S)"
CACHE_BUSTER="${APP_VERSION}-${BUILD_STAMP}"

log "App version: $APP_VERSION"
log "Build stamp: $BUILD_STAMP"

log "Flutter clean..."
"$FLUTTER_BIN" clean

log "Flutter pub get..."
"$FLUTTER_BIN" pub get

log "Flutter build web --release --pwa-strategy=none --no-tree-shake-icons..."
"$FLUTTER_BIN" build web --release --pwa-strategy=none --no-tree-shake-icons

log "Writing deployed version file..."
printf '%s\n' "$APP_VERSION" > build/web/app_version.txt
printf '%s\n' "$CACHE_BUSTER" > build/web/build_stamp.txt

if [ -f build/web/index.html ]; then
  log "Adding version query to flutter_bootstrap.js..."
  sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=$CACHE_BUSTER|g" build/web/index.html
fi

if [ -f build/web/flutter_bootstrap.js ]; then
  log "Adding version query to main.dart.js inside flutter_bootstrap.js when present..."
  sed -i "s|main.dart.js|main.dart.js?v=$CACHE_BUSTER|g" build/web/flutter_bootstrap.js || true
fi

log "Deploying build/web -> $DEST_DIR ..."
if [ "$USE_SUDO_RSYNC" = "1" ]; then
  sudo rsync -av --delete build/web/ "$DEST_DIR"/
else
  rsync -av --delete build/web/ "$DEST_DIR"/
fi

log "Reloading Apache2..."
sudo apachectl configtest
sudo systemctl reload apache2

log "Done."