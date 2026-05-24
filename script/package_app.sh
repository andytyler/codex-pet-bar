#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

APP_NAME="CodexPetBar"
BUNDLE_ID="${BUNDLE_ID:-dev.ajt.CodexPetBar}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
CODESIGN_VALUE="${CODESIGN_IDENTITY:--}"
DIST_DIR=""
CREATE_ZIP=0

usage() {
  cat <<USAGE
Usage: script/package_app.sh [options]

Options:
  -c, --configuration debug|release  Swift build configuration. Default: release
  -o, --output <directory>           Output directory. Default: ./dist
      --version <version>            CFBundleShortVersionString. Default: 0.1.0
      --build-number <number>        CFBundleVersion. Default: git commit count or timestamp
      --sign <identity>              Code signing identity. Use "-" for ad hoc. Default: -
      --no-sign                      Do not code sign the app bundle
      --zip                          Also create a zip archive beside the app bundle
  -h, --help                         Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--configuration)
      CONFIGURATION="${2:?missing value for $1}"
      shift 2
      ;;
    -o|--output)
      DIST_DIR="${2:?missing value for $1}"
      shift 2
      ;;
    --version)
      VERSION="${2:?missing value for $1}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:?missing value for $1}"
      shift 2
      ;;
    --sign)
      CODESIGN_VALUE="${2:?missing value for $1}"
      shift 2
      ;;
    --no-sign)
      CODESIGN_VALUE="none"
      shift
      ;;
    --zip)
      CREATE_ZIP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    debug|release)
      CONFIGURATION="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Configuration must be debug or release." >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_ICON_NAME="CodexAppIcon"
APP_ICON_RESOURCE="$ROOT_DIR/Sources/CodexPetBarCore/Resources/$APP_ICON_NAME.icns"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_SHARED_SUPPORT="$APP_CONTENTS/SharedSupport"
APP_SUPPORT_BIN="$APP_SHARED_SUPPORT/bin"
APP_SUPPORT_SCRIPTS="$APP_SHARED_SUPPORT/script"
APP_SUPPORT_HOOKS="$APP_SHARED_SUPPORT/.codex/hooks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [[ -z "$BUILD_NUMBER" ]]; then
  if BUILD_NUMBER="$(cd "$ROOT_DIR" && git rev-list --count HEAD 2>/dev/null)"; then
    :
  else
    BUILD_NUMBER="$(date +%Y%m%d%H%M)"
  fi
fi

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" --product "$APP_NAME"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "SwiftPM did not produce $BUILD_BINARY." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_SUPPORT_BIN" "$APP_SUPPORT_SCRIPTS" "$APP_SUPPORT_HOOKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod 755 "$APP_BINARY"

if [[ ! -f "$APP_ICON_RESOURCE" ]]; then
  echo "Missing app icon: $APP_ICON_RESOURCE" >&2
  exit 1
fi
cp "$APP_ICON_RESOURCE" "$APP_RESOURCES/"

cp "$ROOT_DIR/script/install_hooks.py" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/script/install_pet.sh" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/script/validate_pet.py" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/.codex/hooks/codex_pet_event.py" "$APP_SUPPORT_HOOKS/"
chmod 755 "$APP_SUPPORT_SCRIPTS/install_hooks.py"
chmod 755 "$APP_SUPPORT_SCRIPTS/install_pet.sh"
chmod 755 "$APP_SUPPORT_SCRIPTS/validate_pet.py"
chmod 755 "$APP_SUPPORT_HOOKS/codex_pet_event.py"

cat >"$APP_SUPPORT_BIN/codex-pet-bar" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  codex-pet-bar
  codex-pet-bar --add-codex-hooks [--workspace <path> | <path>]

Options:
  --add-codex-hooks              Install user-level CodexPetBar hooks into ~/.codex/hooks.json.
  --add-codex-hooks <path>       Compatibility form for workspace-local hooks.
  --add-codex-hooks --workspace <path>
                                 Install workspace-local hooks into <path>/.codex/hooks.json.
  -h, --help                     Show this help.
USAGE
}

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUPPORT_DIR="$APP_DIR/Contents/SharedSupport"

case "${1:-}" in
  "")
exec /usr/bin/open -n "$APP_DIR"
    ;;
  --add-codex-hooks)
    shift
    exec /usr/bin/python3 "$SUPPORT_DIR/script/install_hooks.py" "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac
SH

cat >"$APP_SUPPORT_BIN/codex-pet-install-hooks" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 "$SUPPORT_DIR/script/install_hooks.py" "$@"
SH

cat >"$APP_SUPPORT_BIN/codex-pet-install-pet" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$SUPPORT_DIR/script/install_pet.sh" "$@"
SH

cat >"$APP_SUPPORT_BIN/codex-pet-validate-pet" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 "$SUPPORT_DIR/script/validate_pet.py" "$@"
SH

chmod 755 "$APP_SUPPORT_BIN/codex-pet-bar"
chmod 755 "$APP_SUPPORT_BIN/codex-pet-install-hooks"
chmod 755 "$APP_SUPPORT_BIN/codex-pet-install-pet"
chmod 755 "$APP_SUPPORT_BIN/codex-pet-validate-pet"

copied_resource_bundle=0
while IFS= read -r -d '' bundle_path; do
  cp -R "$bundle_path" "$APP_RESOURCES/"
  while IFS= read -r -d '' resource_file; do
    cp "$resource_file" "$APP_RESOURCES/"
  done < <(find "$bundle_path" -maxdepth 1 -type f -print0)
  copied_resource_bundle=1
done < <(find "$BUILD_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

if [[ "$copied_resource_bundle" -eq 0 ]]; then
  echo "warning: no SwiftPM resource bundles found in $BUILD_DIR" >&2
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf "APPL????" >"$APP_CONTENTS/PkgInfo"
xattr -cr "$APP_BUNDLE"

if [[ "$CODESIGN_VALUE" != "none" ]]; then
  codesign_args=(--force --deep --sign "$CODESIGN_VALUE")
  if [[ "$CODESIGN_VALUE" != "-" ]]; then
    codesign_args+=(--options runtime --timestamp)
  fi
  codesign "${codesign_args[@]}" "$APP_BUNDLE"
fi

if [[ "$CREATE_ZIP" -eq 1 ]]; then
  ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macos.zip"
  rm -f "$ZIP_PATH"
  (cd "$DIST_DIR" && ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$ZIP_PATH")
  echo "Archive: $ZIP_PATH"
fi

echo "App: $APP_BUNDLE"
