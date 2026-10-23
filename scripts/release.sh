#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 1. Determine Version
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(grep 'public static let currentVersion' "$PROJECT_DIR/Sources/TranskriptHubCore/Updates/UpdateChecker.swift" | sed -E 's/.*"([^"]+)".*/\1/')
fi
VERSION="${VERSION#v}" # Strip leading 'v' if provided
TAG="v$VERSION"

echo "=========================================="
echo "  Transkript Hub Release: $TAG"
echo "=========================================="

# 2. Update Version in UpdateChecker.swift
sed -i '' -E "s/(public static let currentVersion = \")[^\"]+(\")/\1$VERSION\2/" "$PROJECT_DIR/Sources/TranskriptHubCore/Updates/UpdateChecker.swift"
echo "✓ UpdateChecker.currentVersion set to $VERSION"

# 3. Run Unit Tests
echo "Running unit tests..."
swift test
echo "✓ All tests passed."

# 4. Package Release DMG
echo "Packaging release DMG..."
chmod +x "$PROJECT_DIR/scripts/package_dmg.sh"
"$PROJECT_DIR/scripts/package_dmg.sh" "$VERSION"
echo "✓ DMG built at dist/TranskriptHub.dmg"

# 5. Git Commit & Tag
echo "Committing release changes..."
git add -A
if ! git diff --cached --quiet; then
    git commit -m "chore(release): $TAG"
fi

# Check if tag already exists locally, update or create
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists locally, recreating..."
    git tag -d "$TAG"
fi
git tag -a "$TAG" -m "Transkript Hub $TAG"
echo "✓ Git tag $TAG created."

# 6. Push Commit & Tag to GitHub
echo "Pushing to GitHub origin..."
git push origin main
git push origin "$TAG" --force
echo "✓ Pushed main and $TAG to GitHub."

# 7. Create GitHub Release & Upload Asset via GitHub API
echo "Publishing GitHub Release via API..."
TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill 2>/dev/null | grep password | cut -d= -f2 || true)

if [ -z "$TOKEN" ]; then
    echo "Notice: No GitHub token found in git credentials. GitHub Actions will handle the release asset upload upon push."
    exit 0
fi

REPO="Akifulutas/Transkript-Hub"
RELEASE_TITLE="Transkript Hub $TAG"
RELEASE_BODY="## Transkript Hub $TAG

### 🚀 Yenilikler ve İyileştirmeler
- **Kuyruk Temizleme Kalıcılığı (Tombstone Tracking)**: Silinen kuyruk öğeleri ve Apple Sesli Notlar uygulama yeniden başlatıldığında tekrar kuyruğa gelmez.
- **Toplu Kuyruk Yönetimi**: Seçili öğeleri tek tıkla toplu olarak temizleme desteği.
- **Modern Sağ Hizalı Araç Çubuğu**: '+ Medya Ekle' ve 'Ayarlar' butonları macOS penceresinin en sağına sabitlendi.
- **İkili Ses Kaydı Göstergesi**: Canlı ses kaydı kartı hem Mikrofon hem de Mac Sistem Sesi (Toplantı/Video) kaynaklarını açıkça gösterir.
- **Hızlı Sağ Tık Menüsü**: Canlı ses kaydı kartına sağ tıklayarak anında mikrofon veya sistem sesi kaydı başlatabilme.

### 📦 İndirme
Aşağıdaki \`TranskriptHub.dmg\` dosyasını indirip doğrudan Uygulamalar (Applications) klasörünüze taşıyabilirsiniz."

# Check if release already exists on GitHub
EXISTING_ID=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep -o '"id": [0-9]*' | head -1 | awk '{print $2}' || true)

if [ -n "$EXISTING_ID" ]; then
    echo "Release already exists (ID: $EXISTING_ID). Deleting existing release to recreate..."
    curl -s -X DELETE -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/releases/$EXISTING_ID" >/dev/null
fi

CREATE_PAYLOAD=$(cat <<EOF
{
  "tag_name": "$TAG",
  "name": "$RELEASE_TITLE",
  "body": $(printf '%s' "$RELEASE_BODY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "draft": false,
  "prerelease": false
}
EOF
)

RELEASE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d "$CREATE_PAYLOAD")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | grep -o '"id": [0-9]*' | head -1 | awk '{print $2}')
HTML_URL=$(echo "$RELEASE_RESPONSE" | grep -o '"html_url": "[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$RELEASE_ID" ]; then
    echo "Error creating release. Response:"
    echo "$RELEASE_RESPONSE"
    exit 1
fi

echo "✓ Release created: $HTML_URL"

# Upload DMG Asset
DMG_FILE="$PROJECT_DIR/dist/TranskriptHub.dmg"
if [ -f "$DMG_FILE" ]; then
    echo "Uploading TranskriptHub.dmg to GitHub Release ($RELEASE_ID)..."
    UPLOAD_URL="https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=TranskriptHub.dmg"
    
    UPLOAD_RESPONSE=$(curl -s -X POST \
        -H "Authorization: token $TOKEN" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$DMG_FILE" \
        "$UPLOAD_URL")
    
    DOWNLOAD_URL=$(echo "$UPLOAD_RESPONSE" | grep -o '"browser_download_url": "[^"]*"' | head -1 | cut -d'"' -f4)
    echo "✓ TranskriptHub.dmg uploaded successfully!"
    echo "  Download URL: $DOWNLOAD_URL"
fi

echo "=========================================="
echo "🎉 Release $TAG is live on GitHub!"
echo "   $HTML_URL"
echo "=========================================="
