#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Transkript Hub"
BUNDLE_NAME="TranskriptHub.app"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$BUNDLE_NAME"
DMG_PATH="$DIST_DIR/TranskriptHub.dmg"

echo "=== Transkript Hub DMG Packager ==="
echo "1. Building release binaries..."
swift build -c release

echo "2. Preparing distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"

echo "3. Copying binaries and dependencies..."
cp "$BUILD_DIR/TranskriptHubApp" "$APP_DIR/Contents/MacOS/TranskriptHub"
chmod +x "$APP_DIR/Contents/MacOS/TranskriptHub"

# Copy whisper.framework, AppIcon and PrivacyInfo
cp -R "$PROJECT_DIR/Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework" "$APP_DIR/Contents/Frameworks/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [ -f "$PROJECT_DIR/Resources/PrivacyInfo.xcprivacy" ]; then
    cp "$PROJECT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
fi

echo "4. Configuring RPATH and dynamic linker..."
install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_DIR/Contents/MacOS/TranskriptHub" 2>/dev/null || true

echo "5. Generating Info.plist..."
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
    <key>CFBundleDisplayName</key>
    <string>Transkript Hub</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>1.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Transkript Hub, ses kayıtlarınızı doğrudan metne dönüştürmek için mikrofonunuza erişim sağlar.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

echo "6. Code signing and Gatekeeper quarantine cleanup..."
xattr -cr "$APP_DIR" || true

ENTITLEMENTS="$PROJECT_DIR/Resources/TranskriptHub.entitlements"
SIGN_IDENTITY="-"

# Sign embedded framework first (bottom-up signing)
codesign --force --options runtime -s "$SIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/whisper.framework" 2>/dev/null || codesign --force -s "$SIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/whisper.framework"

# Sign main application bundle with Hardened Runtime and Entitlements
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" -s "$SIGN_IDENTITY" "$APP_DIR" 2>/dev/null || codesign --force --entitlements "$ENTITLEMENTS" -s "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force -s "$SIGN_IDENTITY" "$APP_DIR"
fi

echo "7. Creating DMG staging layout..."
DMG_STAGING="$DIST_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "8. Creating DMG archive (hdiutil)..."
rm -f "$DMG_PATH"
hdiutil create -volname "Transkript Hub" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "✅ Success! DMG file ready:"
ls -lh "$DMG_PATH"
