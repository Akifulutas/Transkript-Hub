# Transkript Hub 🎙️⚡

**Apple Silicon Mac'ler için Tamamen Yerel, Çevrimdışı ve Sıfır Bağımlılıklı Transkripsiyon Uygulaması.**

Transkript Hub; YouTube videolarını (tekil veya toplu) ve ses dosyalarını (Voice Memos, M4A, MP3, WAV vb.) Mac'inizin kendi GPU çipini (Metal) doğrudan kullanarak **hiçbir harici sunucuya ses göndermeden** ve **Buzz, Python, FFmpeg veya Terminal gerektirmeden** yüksek hızda metne dönüştürür.

---

## ✨ Özellikler

- **⚡ Apple Silicon Metal Hızlandırması:** `whisper.cpp` resmi C/C++ motoru doğrudan Mac GPU'nuzda çalışır (gerçek zamanın 10-20 katı hızında transkripsiyon).
- **🚫 Sıfır Harici Kurulum:** Buzz, Homebrew, Python, FFmpeg veya Terminal komutları kurmak **gerekmez**. Tek bir DMG indirip çalıştırın.
- **🛡️ Dayanıklı Toplu İşlem (22/25 Resiliency):** 25 videoluk bir listede bazı videolar 403 veya üyelik hatası verse bile sistem durmaz; tamamlanan tüm videolar sırasıyla tek bir temiz TXT dosyasında birleştirilir.
- **📋 Akıllı Pano İzleyici (Clipboard Monitor):** Safari veya Chrome'da bir YouTube linki kopyaladığınız anda arka planda algılanır ve oturum listesine eklenir. Şifre yöneticilerini (1Password vb.) rahatsız etmez.
- **📁 İzlenen Klasörler (Folder Watcher):** iCloud Drive veya belirlenen bir klasöre iPhone'dan ya da Mac'ten ses kaydı düştüğü anda otomatik algılayıp arka planda transkript eder.
- **💾 Atomik ve Çakışmasız Çıktı:** Tekil videolarda doğrudan `Başlık.txt` üretir; asla mevcut dosyaların üzerine yazmaz (`Başlık (2).txt`).
- **🔒 %100 Gizlilik:** Sesleriniz asla harici bir bulut sunucusuna gönderilmez; tamamen Mac'inizde işlenir.

---

## 🚀 Kurulum

1. [GitHub Releases](../../releases) sayfasından en son **`TranskriptHub.dmg`** dosyasını indirin.
2. DMG dosyasını açın ve **Transkript Hub** uygulamasını **Applications** klasörüne sürükleyin.
3. Uygulamayı ilk kez açarken:
   - macOS Gatekeeper uyarısı verirse: Uygulamaya sağ tıklayıp **Aç (Open)** deyin veya *Sistem Ayarları -> Gizlilik ve Güvenlik* altından izin verin.
4. Hepsi bu kadar!

---

## 🛠️ Mimari ve Bileşenler

```
TranskriptHub
├── TranskriptHubApp (SwiftUI Arayüzü & Menü Çubuğu)
└── TranskriptHubCore (Çekirdek Kütüphane)
    ├── Audio (AVFoundation ses çözücü & doğrulayıcı)
    ├── Transcription (whisper.cpp xcframework, Metal GPU motoru, ModelManager)
    ├── Tools (İzole yt-dlp & Deno istemcisi)
    ├── Database (GRDB.swift SQLite kalıcı iş kuyruğu & kurtarma)
    ├── Batch (BatchAssembler, OutputFormatter Format-Version 1)
    └── System (ClipboardMonitor, FolderWatcher)
```

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) ile lisanslanmıştır.
Kullanılan alt bileşenler (`whisper.cpp`, `GRDB.swift`, `yt-dlp`, `Deno`) kendi açık kaynak lisanslarına tabidir.
