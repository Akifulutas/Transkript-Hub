# Transkript Hub — Tasarım Sistemi & Mimari Standartları (design.md)
*Sürüm: 2026.1 • Standart: Apple HIG & Liquid Glass • İlke: Anti-AI Slop & Eyleme Dönük Mimari*

---

## 1. Temel Felsefe: Anti-AI Slop & İnsan Odaklı Masaüstü Ergonomisi

Yapay zeka araçlarının varsayılan tasarım refleksleri (her öğeye eşit ağırlık verme, her şeyi kutu içine alma, merkeze hizalama ve pasif istatistikler sunma) bu sistemde kesin olarak yasaklanmıştır.

1. **Özellik Değil, Aksiyon Odaklı Bilgi Mimarisi:**
   - Ekranda "Toplam 31 Video" gibi pasif veritabanı sayıları yerine ilk iki saniyede net aksiyon bilgisi sunulur:
     `"29 Başarılı • 2 İndirilemeyen Video (Yeniden Dene) • 1 Yerel Klasör Dinleniyor"`
   - Hatalı öğeler (`[FAILED]`) listenin en tepesinde, kehribar/kırmızı Liquid Glass cam parlamasıyla **"Müdahale Gerekiyor"** grubunda toplanır.
2. **İç İçe Kart (Double-Nesting) Yasağı:**
   - Kart içine çerçeveli kart yerleştirilemez (`padding üstüne padding` yasağı).
   - Gruplama işlemleri kutularla değil; 13pt tipografik hiyerarşi, negatif boşluk (whitespace) ve tek piksellik ince ayırıcılarla yapılır.
3. **Sıfır Temaslı Veri Alma (Zero-Touch Ingestion & Confidence UI):**
   - Panoya bir YouTube linki kopyalandığında veya iCloud / Voice Memos klasörüne yeni bir ses düştüğünde arayüz sıfır tıklamayla bunu algılar.
   - Algılanan yeni öge, zaman çizelgesinde *"Yeni Yakalandı • İşlenmeyi Bekliyor"* canlı rozetiyle güven arayüzü (Confidence UI) biçiminde sunulur.
4. **Tekil Terim & Davranış Tutarlılığı:**
   - Aynı işlem her yerde tek bir kelimeyle ifade edilir (örneğin "Transkripti Başlat").

---

## 2. Zorunlu Durum Matrisi (The 8-State Matrix)

| Durum (State) | Tasarım ve Davranış Kuralı | Transkript Hub Karşılığı |
|---|---|---|
| **1. İlk Kullanım (Empty)** | Tam ekran odak, tek bir ana aksiyona yönlendiren minimalist ikon ve açıklama. | "Kuyruk Boş. YouTube bağlantısı yapıştırın veya ses dosyasını sürükleyin." |
| **2. Yükleniyor (Loading)** | İskelet (skeleton) veya gerçek zamanlı adım ilerleme çubuğu. | "29/31 Video işleniyor... Ses ayrıştırılıyor (GPU Metal)." |
| **3. Başarılı (Success)** | Renk kodlu rozet ve anında erişilebilir çıktı aksiyonları. | Yeşil cam rozeti, "Kopyala", "Finder'da Göster" tek tık butonları. |
| **4. Kısmi / Tam Hata (Error)** | Neden başarısız olduğunu açıklayan ve çıkış yolu sunan net hata kartı. | `[FAILED: 403 / İndirilemedi]` -> "Çerezleri güncelle veya Tek Tıkla Yeniden Dene" |
| **5. Sonuç Yok (No Results)** | Arama/filtre sonucu boşsa öneri ve temizleme çıkışı. | "Aradığınız kelime bulunamadı. Filtreyi Sıfırla (Esc)." |
| **6. Devre Dışı (Disabled)** | Pasif butonun neden tıklanamadığını açıklayan mikro-ipucu (tooltip). | Kuyruk boşken pasif "Transkripti Başlat" butonu -> "Önce en az 1 link veya ses ekleyin." |
| **7. Onay / Geri Alma (Confirmation/Undo)** | Yıkıcı işlemlerde diyalog yerine 5 saniyelik "Geri Al" (Undo) bildirim çubuğu. | Kuyruk temizlendiğinde ekranda beliren `Geri Al (Undo)` cam bildirim kapsülü. |
| **8. Kurtarma (Recovery)** | Beklenmeyen kapanma sonrası oturumu koruyan otomatik durum kurtarma. | SQLite durum makinesiyle 31 videoluk işlemde kalınan videodan devam etme. |

---

## 3. Liquid Glass UI (Sıvı Cam) Fizik Kuralları

Apple'ın modern tasarım dili olan Liquid Glass, SwiftUI'da aşağıdaki kurallarla uygulanır:

1. **H / 2 Kapsül Geometrisi (Corner Radius Rule):**
   - Yüzen aksiyon butonları, durum rozetleri ve filtre pillerinde köşe yarıçapı öğe yüksekliğinin tam yarısıdır:
     - `Height: 44pt` -> `CornerRadius: 22pt`
     - `Height: 36pt` -> `CornerRadius: 18pt`
     - `Height: 28pt` -> `CornerRadius: 14pt`
     - `Height: 20pt` -> `CornerRadius: 10pt`
2. **Kırılma (Refraction), Buzlanma (Frost) & 1px Specular Border Glow:**
   - Zeminler `.ultraThinMaterial` ile ışığı kırar.
   - Her cam konteynerin üst ve sol kenarında 1 piksellik yarı saydam gradyanlı ışık çizgisi (`specular highlight`) bulunur:
     `LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)`
3. **Dinamik Genişleyen Konteynerler (Hug Contents):**
   - Tüm buton ve durum rozetleri sabit genişlikte değil, içindeki metin değiştikçe `.spring(response: 0.35, dampingFraction: 0.78)` animasyonuyla yumuşakça esneyip daralır.
4. **Hafif Ambiyans Gölgesi:**
   - Cam öğelerin altında derinlik yaratan yumuşak gölge:
     `.shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)`

---

## 4. Tipografi ve Yerleşim Sistemi (13pt Temel Masaüstü Standardı)

macOS ekran ergonomisi 13pt temel metin boyutu üzerine kuruludur:

- **Büyük Başlık (Header):** 18pt • Bold • `.system(size: 18, weight: .bold, design: .default)`
- **Alt Başlık / Bölüm Etiketi:** 11pt • Semibold • Uppercase • Tracking: 0.8pt • `.secondary`
- **Gövde Metni (Body):** 13pt • Regular • LineSpacing: 3pt
- **Okuma Alanı (Transcript Reader):** 13pt-22pt dinamik • Serif (`.serif` veya `.system(..., design: .serif)`) • LineSpacing: 6pt
- **Meta Veri / Zaman Damgası / Sayaç:** 11pt • Monospaced • `.system(size: 11, weight: .medium, design: .monospaced)`
- **Mikro Etiket / Rozet:** 10pt • Semibold • `.system(size: 10, weight: .semibold)`

---

## 5. Çift Eksenli macOS Ergonomisi (3 Sütunlu NavigationSplitView)

```text
┌─────────────────┬──────────────────────────────┬───────────────────────────────────────────┐
│ SÜTUN 1: SIDEBAR│ SÜTUN 2: CONTENT & QUEUE     │ SÜTUN 3: TRANSCRIPT READER & INSPECTOR    │
│                 │                              │                                           │
│ ◉ Transkript    │ [Actionable Header: 29/2/1]  │ [Liquid Glass Header: Title & Actions]    │
│                 │ ┌──────────────────────────┐ │                                           │
│ • Kuyruk (31)   │ │ ⚠️ MÜDAHALE GEREKİYOR (2) │ │ "Metin içinde ara..."     [A-] [A+] [Copy]│
│ • Geçmiş        │ │  (Amber Liquid Glass)    │ │                                           │
│ • İzlenen Klasör│ └──────────────────────────┘ │ ───────────────────────────────────────── │
│ • Ayarlar       │ ┌──────────────────────────┐ │                                           │
│                 │ │ İŞLENİYOR & KUYRUK (1)   │ │  "Transkript içeriği serif tipografide    │
│ 🟢 Klasör Canlı │ │ TAMAMLANANLAR (28)       │ │   akıcı ve rahatça okunabilir satırlar    │
│                 │ └──────────────────────────┘ │   halinde listelenir..."                  │
│                 │ [⌘K Paleti • Yoğunluk Seçici]│                                           │
└─────────────────┴──────────────────────────────┴───────────────────────────────────────────┘
```

---

## 6. Klavye Öncelikli Etkileşimler (Keyboard-First Ergonomics)

- `⌘ + K` : Yüzen Liquid Glass Komut & Arama Paleti (Floating Command Palette)
- `⌘ + V` : Panodaki tüm geçerli YouTube linklerini sıfır temasla kuyruğa alma
- `⌘ + Return` : Transkripti Başlat
- `⌘ + ⇧ + C` : Seçili transkriptin temiz metnini anında panoya kopyalama
- `Space` : Ses kaydı / kaynak medya Quick Look önizlemesi
- `Esc` : Arama veya yüzen paletten çıkış / Filtreyi temizleme
