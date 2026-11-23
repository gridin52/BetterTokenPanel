#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Для сборки нужны macOS 13+ и Command Line Tools: xcode-select --install' >&2
  exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Установите инструменты Apple: xcode-select --install' >&2
  exit 1
fi
APP="$ROOT/dist/BetterTokenPanel.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
xcrun swiftc -parse-as-library -swift-version 5 -O \
  -sdk "$SDK" -target "${ARCH}-apple-macosx13.0" \
  "$ROOT"/Sources/BetterTokenPanel/*.swift \
  -framework AppKit -framework SwiftUI -framework WebKit -framework Security -framework UserNotifications -framework ServiceManagement \
  -o "$APP/Contents/MacOS/BetterTokenPanel"
cp "$ROOT/Sources/BetterTokenPanel/BalanceReader.js" "$APP/Contents/Resources/BalanceReader.js"
cp "$ROOT/Sources/BetterTokenPanel/PanelDetector.js" "$APP/Contents/Resources/PanelDetector.js"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BetterTokenPanel</string>
<key>CFBundleIdentifier</key><string>com.bettertokenpanel.app</string>
<key>CFBundleName</key><string>BetterTokenPanel</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Готово: $APP"
echo 'Перенесите приложение в Applications и откройте его.'
