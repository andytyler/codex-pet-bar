#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

APP_NAME="CodexPetBar"
BUNDLE_ID="${BUNDLE_ID:-dev.ajt.CodexPetBar}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHITECTURE="${ARCHITECTURE:-arm64}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
CODESIGN_VALUE="${CODESIGN_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-codex-pet-bar-notary}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"
DIST_DIR=""
CREATE_ZIP=0

usage() {
  cat <<USAGE
Usage: script/package_app.sh [options]

Options:
  -c, --configuration debug|release  Swift build configuration. Default: release
      --arch arm64                  Target architecture. CodexPetBar ships for Apple Silicon only.
  -o, --output <directory>           Output directory. Default: ./dist
      --version <version>            CFBundleShortVersionString. Default: 0.1.0
      --build-number <number>        CFBundleVersion. Default: git commit count or timestamp
      --sign <identity>              Code signing identity. Use "-" for ad hoc. Default: -
      --no-sign                      Do not code sign the app bundle
      --notarize                     Submit the signed app to Apple's notary service and staple the ticket
      --notary-profile <profile>     notarytool keychain profile. Default: codex-pet-bar-notary
      --notary-timeout <duration>    notarytool wait timeout. Default: 30m
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
    --arch)
      ARCHITECTURE="${2:?missing value for $1}"
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
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --notary-profile)
      NOTARY_KEYCHAIN_PROFILE="${2:?missing value for $1}"
      shift 2
      ;;
    --notary-timeout)
      NOTARY_TIMEOUT="${2:?missing value for $1}"
      shift 2
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

if [[ "$ARCHITECTURE" != "arm64" ]]; then
  echo "CodexPetBar ships for Apple Silicon only; --arch must be arm64." >&2
  exit 2
fi

if [[ "$NOTARIZE" != "0" && "$NOTARIZE" != "1" ]]; then
  echo "NOTARIZE must be 0 or 1." >&2
  exit 2
fi

if [[ "$NOTARIZE" -eq 1 && ( "$CODESIGN_VALUE" == "-" || "$CODESIGN_VALUE" == "none" ) ]]; then
  echo "Notarization requires a Developer ID Application signing identity. Pass --sign or set CODESIGN_IDENTITY." >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd -P)"
APP_ICON_NAME="CodexAppIcon"
APP_ICON_RESOURCE="$ROOT_DIR/Sources/CodexPetBarCore/Resources/$APP_ICON_NAME.icns"
# File Provider managed output folders (including Documents) can attach Finder
# metadata while an app is assembled. Build and sign on an unmanaged filesystem.
PACKAGE_WORK_DIR="$(mktemp -d /private/tmp/codexpetbar-package.XXXXXX)"
KEEP_PACKAGE_WORK_DIR=0
cleanup_package() {
  if [[ "$KEEP_PACKAGE_WORK_DIR" -eq 0 ]]; then rm -rf "$PACKAGE_WORK_DIR"; fi
}
trap cleanup_package EXIT
FILE_PROVIDER_OUTPUT="$(/usr/bin/python3 - "$DIST_DIR" <<'PYTHON'
from pathlib import Path
import subprocess
import sys
path = Path(sys.argv[1])
managed = False
for directory in (path, *path.parents):
    try:
        attributes = subprocess.run(["/usr/bin/xattr", str(directory)], capture_output=True, text=True).stdout.splitlines()
        if any(name.startswith("com.apple.fileprovider.") for name in attributes):
            managed = True
            break
    except OSError:
        pass
print("1" if managed else "0")
PYTHON
)"
FINAL_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BUNDLE="$PACKAGE_WORK_DIR/$APP_NAME.app"
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
swift build --build-system native -c "$CONFIGURATION" --arch "$ARCHITECTURE" --product "$APP_NAME"
BUILD_DIR="$(swift build --build-system native -c "$CONFIGURATION" --arch "$ARCHITECTURE" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "SwiftPM did not produce $BUILD_BINARY." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_SUPPORT_BIN" "$APP_SUPPORT_SCRIPTS" "$APP_SUPPORT_HOOKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod 755 "$APP_BINARY"

BUILT_ARCHITECTURES="$(lipo -archs "$APP_BINARY")"
if [[ "$BUILT_ARCHITECTURES" != "arm64" ]]; then
  echo "Packaged binary must be arm64-only; found: $BUILT_ARCHITECTURES" >&2
  exit 1
fi

if [[ ! -f "$APP_ICON_RESOURCE" ]]; then
  echo "Missing app icon: $APP_ICON_RESOURCE" >&2
  exit 1
fi
cp "$APP_ICON_RESOURCE" "$APP_RESOURCES/"

cp "$ROOT_DIR/script/install_hooks.py" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/script/install_pet.sh" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/script/install_pet.py" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/script/validate_pet.py" "$APP_SUPPORT_SCRIPTS/"
cp "$ROOT_DIR/.codex/hooks/codex_pet_event.py" "$APP_SUPPORT_HOOKS/"
chmod 755 "$APP_SUPPORT_SCRIPTS/install_hooks.py"
chmod 755 "$APP_SUPPORT_SCRIPTS/install_pet.sh"
chmod 755 "$APP_SUPPORT_SCRIPTS/install_pet.py"
chmod 755 "$APP_SUPPORT_SCRIPTS/validate_pet.py"
chmod 755 "$APP_SUPPORT_HOOKS/codex_pet_event.py"

cat >"$APP_SUPPORT_BIN/codex-pet-bar" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  codex-pet-bar
  codex-pet-bar --add-hooks [--provider codex|claude|cursor|all]
  codex-pet-bar --add-codex-hooks [--workspace <path> | <path>]

Options:
  --add-hooks                    Install user-level pet hooks. Defaults to Codex; pass
                                 --provider all for Codex, Claude Code, and Cursor.
  --add-codex-hooks              Backwards-compatible alias for --add-hooks.
  --add-codex-hooks <path>       Compatibility form for workspace-local hooks.
  --add-codex-hooks --workspace <path>
                                 Install workspace-local hooks into <path>/.codex/hooks.json.
  -h, --help                     Show this help.
USAGE
}

SCRIPT_PATH="${BASH_SOURCE[0]}"
for ((hop = 0; hop < 40; hop++)); do
  [[ -L "$SCRIPT_PATH" ]] || break
  SCRIPT_PARENT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" == /* ]] || SCRIPT_PATH="$SCRIPT_PARENT/$SCRIPT_PATH"
done
if [[ -L "$SCRIPT_PATH" ]]; then
  echo "Could not resolve launcher symlink chain." >&2
  exit 1
fi
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
SUPPORT_DIR="$APP_DIR/Contents/SharedSupport"

case "${1:-}" in
  "")
    exec /usr/bin/open "$APP_DIR"
    ;;
  --add-hooks|--add-codex-hooks)
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

SCRIPT_PATH="${BASH_SOURCE[0]}"
for ((hop = 0; hop < 40; hop++)); do
  [[ -L "$SCRIPT_PATH" ]] || break
  SCRIPT_PARENT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" == /* ]] || SCRIPT_PATH="$SCRIPT_PARENT/$SCRIPT_PATH"
done
if [[ -L "$SCRIPT_PATH" ]]; then
  echo "Could not resolve launcher symlink chain." >&2
  exit 1
fi
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
SUPPORT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
exec /usr/bin/python3 "$SUPPORT_DIR/script/install_hooks.py" "$@"
SH

cat >"$APP_SUPPORT_BIN/codex-pet-install-pet" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
for ((hop = 0; hop < 40; hop++)); do
  [[ -L "$SCRIPT_PATH" ]] || break
  SCRIPT_PARENT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" == /* ]] || SCRIPT_PATH="$SCRIPT_PARENT/$SCRIPT_PATH"
done
if [[ -L "$SCRIPT_PATH" ]]; then
  echo "Could not resolve launcher symlink chain." >&2
  exit 1
fi
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
SUPPORT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
exec "$SUPPORT_DIR/script/install_pet.sh" "$@"
SH

cat >"$APP_SUPPORT_BIN/codex-pet-validate-pet" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
for ((hop = 0; hop < 40; hop++)); do
  [[ -L "$SCRIPT_PATH" ]] || break
  SCRIPT_PARENT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" == /* ]] || SCRIPT_PATH="$SCRIPT_PARENT/$SCRIPT_PATH"
done
if [[ -L "$SCRIPT_PATH" ]]; then
  echo "Could not resolve launcher symlink chain." >&2
  exit 1
fi
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
SUPPORT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
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
  <key>LSMultipleInstancesProhibited</key>
  <true/>
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
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  NOTARY_ZIP_PATH="$PACKAGE_WORK_DIR/$APP_NAME-$VERSION-notary.zip"
  rm -f "$NOTARY_ZIP_PATH"
  (cd "$PACKAGE_WORK_DIR" && ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$NOTARY_ZIP_PATH")
  xcrun notarytool submit "$NOTARY_ZIP_PATH" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait \
    --timeout "$NOTARY_TIMEOUT"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  rm -f "$NOTARY_ZIP_PATH"
fi

if [[ "$CREATE_ZIP" -eq 1 ]]; then
  ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macos.zip"
  LATEST_ZIP_PATH="$DIST_DIR/$APP_NAME-macos.zip"
  rm -f "$ZIP_PATH" "$LATEST_ZIP_PATH"
  WORK_ZIP_PATH="$PACKAGE_WORK_DIR/$APP_NAME-$VERSION-macos.zip"
  (cd "$PACKAGE_WORK_DIR" && ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$WORK_ZIP_PATH")
  # Verify the distributable's actual extracted bytes before copying it into a
  # managed output folder. The zip itself is immune to bundle Finder metadata.
  mkdir "$PACKAGE_WORK_DIR/archive-check"
  ditto -x -k "$WORK_ZIP_PATH" "$PACKAGE_WORK_DIR/archive-check"
  if [[ "$CODESIGN_VALUE" != "none" ]]; then
    codesign --verify --deep --strict --verbose=2 "$PACKAGE_WORK_DIR/archive-check/$APP_NAME.app"
  fi
  cp "$WORK_ZIP_PATH" "$ZIP_PATH"
  cp "$ZIP_PATH" "$LATEST_ZIP_PATH"
  echo "Archive: $ZIP_PATH"
  echo "Latest archive: $LATEST_ZIP_PATH"
fi

# File Provider can reattach forbidden FinderInfo seconds after a successful
# copy/verification. Keep the raw bundle unmanaged when the output is synced;
# the zip is the durable distributable, and this path supports local validation.
if [[ "$FILE_PROVIDER_OUTPUT" -eq 1 ]]; then
  rm -rf "$FINAL_APP_BUNDLE"
  KEEP_PACKAGE_WORK_DIR=1
  FINAL_APP_BUNDLE="$APP_BUNDLE"
  rm -rf "$PACKAGE_WORK_DIR/archive-check"
  rm -f "$PACKAGE_WORK_DIR/$APP_NAME-$VERSION-macos.zip"
  echo "File Provider output detected: the loose app is retained in private temporary storage."
  echo "Distribute the zip; temporary app storage may be cleared by macOS."
else
  rm -rf "$FINAL_APP_BUNDLE"
  ditto --norsrc --noextattr --noacl "$APP_BUNDLE" "$FINAL_APP_BUNDLE"
  xattr -dr com.apple.FinderInfo "$FINAL_APP_BUNDLE" 2>/dev/null || true
  xattr -dr com.apple.ResourceFork "$FINAL_APP_BUNDLE" 2>/dev/null || true
fi
if [[ "$CODESIGN_VALUE" != "none" ]]; then
  codesign --verify --deep --strict --verbose=2 "$FINAL_APP_BUNDLE"
fi
printf '%s\n' "$FINAL_APP_BUNDLE" >"$DIST_DIR/CodexPetBar-app-path.txt"
echo "App: $FINAL_APP_BUNDLE"
