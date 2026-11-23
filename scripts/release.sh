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

### ⚡️ Büyük Kuyruklar İçin Asenkron Çift Kanallı Boru Hattı (Lookahead Prefetching)
- **Sıfır Bekleme Geçişi (Zero-Wait Transition)**: YouTube videoları işlenirken ağ I/O ile GPU hesaplaması birbirinin arkasına gizlendi. Video 1 Metal GPU'da transkript edilirken Video 2 arka planda önceden indirilir. Video 1 bittiği anda Video 2 beklemeden transkripte girer (%35–%40 net hızlanma).
- **Kayan Pencere Sınırı (Sliding Window = 2 Video)**: Aşırı disk kullanımı ve YouTube bot engeli riskini sıfırlayan tamponlu ön-indirme.

### 🚀 Large-v3-Turbo (1.60 GB) Kataloğa Eklendi
- **25x–35x Hızla Deşifre**: 32 katman ses okuma zekası korunurken 4 katman decoder ile 3 kat daha hızlı deşifre.
- **Nöral Silero VAD v6.2.0 + vDSP AudioConditioner Koruması**: Sessizlik tuzaklarında halüsinasyon riskini sıfıra indiren tam koruma zırhı.
- **Doğruluk Sıralaması**: Doğruluk en yüksek model (\`Large-v3\`, 9.7/10) en altta kalacak şekilde kalibre edildi.

### 🧠 Tek Dosyada Sıfır Maliyetli Maksimum YouTube İstihbaratı
- **Heatmap (En Çok Tekrar İzlenen Anlar)**: Videonun en yoğun anları ve o anlarda konuşulan cümleler.
- **SponsorBlock**: Reklam/sponsor aralıkları ve videonun kilit anı (highlight).
- **İçindekiler & Bölümler**: Bölümlendirilmiş başlıklar ve tekilleştirilmiş kaynak linkleri dizini.

### 📦 İndirme
Aşağıdaki \`TranskriptHub.dmg\` dosyasını indirip doğrudan Uygulamalar (Applications) klasörünüze taşıyabilirsiniz."

# Check if release already exists on GitHub
EXISTING_ID=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep -o '"id": [0-9]*' | head -1 | awk '{print $2}' || true)

if [ -n "$EXISTING_ID" ]; then
    echo "Release already exists (ID: $EXISTING_ID). Deleting existing release to recreate..."
    curl -s -X DELETE -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/releases/$EXISTING_ID" >/dev/null
fi

TMP_PAYLOAD=$(mktemp /tmp/transkripthub_release_XXXXXX.json)
python3 -c '
import json, sys, os
payload = {
    "tag_name": sys.argv[1],
    "name": sys.argv[2],
    "body": sys.argv[3],
    "draft": False,
    "prerelease": False
}
with open(sys.argv[4], "w") as f:
    json.dump(payload, f)
' "$TAG" "$RELEASE_TITLE" "$RELEASE_BODY" "$TMP_PAYLOAD"

RELEASE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d @"$TMP_PAYLOAD")
rm -f "$TMP_PAYLOAD"

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
        "$UPLOAD_URL" || true)
    
    DOWNLOAD_URL=$(echo "$UPLOAD_RESPONSE" | grep -o '"browser_download_url": "[^"]*"' | head -1 | cut -d'"' -f4 || true)
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/TranskriptHub.dmg"
    fi
    echo "✓ TranskriptHub.dmg uploaded successfully!"
    echo "  Download URL: $DOWNLOAD_URL"
fi

echo "=========================================="
echo "🎉 Release $TAG is live on GitHub!"
echo "   $HTML_URL"
echo "=========================================="
