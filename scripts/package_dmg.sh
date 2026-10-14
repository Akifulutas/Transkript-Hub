#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Transkript Hub"
BUNDLE_NAME="TranskriptHub.app"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$BUNDLE_NAME"
DMG_PATH="$DIST_DIR/TranskriptHub.dmg"

echo "=== Transkript Hub DMG Paketleyici ==="
echo "1. Release ikilileri derleniyor..."
swift build -c release

echo "2. Paket dizini hazırlanıyor..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"

echo "3. İkili ve kütüphaneler kopyalanıyor..."
cp "$BUILD_DIR/TranskriptHubApp" "$APP_DIR/Contents/MacOS/TranskriptHub"
chmod +x "$APP_DIR/Contents/MacOS/TranskriptHub"

# Copy whisper.framework
cp -R "$PROJECT_DIR/Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework" "$APP_DIR/Contents/Frameworks/"

echo "4. Info.plist oluşturuluyor..."
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TranskriptHub</string>
    <key>CFBundleIdentifier</key>
    <string>com.akifulutas.TranskriptHub</string>
    <key>CFBundleName</key>
    <string>Transkript Hub</string>
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
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

echo "5. DMG hazırlama dizini oluşturuluyor..."
DMG_STAGING="$DIST_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "6. DMG oluşturuluyor (hdiutil)..."
rm -f "$DMG_PATH"
hdiutil create -volname "Transkript Hub" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "✅ Başarılı! DMG dosyası hazır:"
ls -lh "$DMG_PATH"
