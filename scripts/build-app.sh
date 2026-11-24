#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="debug"
INSTALL_TO_APPS=false

for arg in "$@"; do
  case "$arg" in
    --release) CONFIG="release" ;;
    --install) INSTALL_TO_APPS=true ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--release] [--install]" >&2
      exit 1
      ;;
  esac
done

echo "Building Stratus ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/Stratus"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: Built binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_DIR="$ROOT_DIR/build/Stratus.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Stratus"
chmod +x "$MACOS_DIR/Stratus"

if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Stratus</string>
  <key>CFBundleExecutable</key>
  <string>Stratus</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.stratus.gcp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Stratus</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>CFBundleURLName</key>
      <string>com.stratus.gcp.oauth</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>com.stratus.gcp</string>
        <string>stratus</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

echo "Packaged: $APP_DIR"

if [[ "$INSTALL_TO_APPS" == "true" ]]; then
  mkdir -p "$HOME/Applications"
  DEST_APP="$HOME/Applications/Stratus.app"
  rm -rf "$DEST_APP"
  cp -R "$APP_DIR" "$DEST_APP"
  touch "$DEST_APP"
  echo "Installed: $DEST_APP"
fi
