# Transkript Hub — Master Spesifikasyon (v1)

Aşağıdaki metnin tamamını kodlama yapan yapay zekaya (ör. Claude Code) tek parça ver. Repo açıldığında `docs/SPEC.md` olarak da kaydedilsin. Metin bağlayıcı karar listesidir; "öneri" değil.

### 0. Rol ve çalışma kuralları (AI için)

- Sen bu projenin baş geliştiricisisin. Bu spesifikasyondaki kararlar kesindir; değiştirmek gerekiyorsa kod yazmadan önce gerekçesiyle sor.
- Her milestone'u ayrı bitir. Bir milestone'un kabul kriterleri geçmeden sonrakine geçme.
- Önce `TranskriptHubCore` (UI'sız Swift package) yaz; UI en son gelir. Core'daki her public tip test edilebilir olsun.
- Tüm kod Swift 6, strict concurrency açık. Kod içi isimler İngilizce; UI metinleri `Localizable.xcstrings` içinde Türkçe (varsayılan) + Almanca + İngilizce.
- Harici bağımlılık sadece şunlar: whisper.cpp (xcframework), GRDB.swift, Sparkle 2. Başka paket ekleme; gerekiyorsa sor.
- Legacy shell scriptleri (`docs/legacy-reference/`) davranış referansıdır; kod kopyalama, davranışı yeniden uygula.
- Her işlem idempotent olsun: bir adım yarıda kesilip tekrar çalıştırılırsa aynı sonucu versin.
- Asla kullanıcının orijinal dosyasını silme, taşıma veya değiştirme (yalnız açık ayarla, bkz. §8.5).

### 1. Ürün tanımı

**Transkript Hub**, Apple Silicon Mac'te çalışan, sesleri tamamen yerel olarak metne çeviren tek bir macOS uygulamasıdır. Kullanıcı YouTube linklerini toplar (pano veya yapıştırma) ya da ses dosyası verir; uygulama sesi indirir/okur, whisper.cpp ile transkript eder ve sonucu tek bir düz metin (TXT) dosyası olarak çıktı klasörüne yazar. İşlem bitince geriye yalnız TXT kalır. Kullanıcı Terminal, Homebrew, Python, Buzz, FFmpeg veya yt-dlp kurmaz.

Ana kullanım: "Araştırma için 5–50 YouTube videosu seç → tek birleşik transkript dosyası al."

### 2. Kapsam

**v1 (bu spesifikasyonun konusu)**
- macOS 14+ (Sonoma ve üzeri), yalnız Apple Silicon (arm64).
- YouTube: tek link, çoklu link (yapıştır), pano yakalama (yalnız uygulama açıkken ve yakalama aktifken).
- Yerel dosya: sürükle-bırak, dosya seçici. Formatlar: AVFoundation'ın açabildiği her şey (m4a, mp3, wav, aac, caf, aiff, mp4/mov ses izi).
- İzlenen klasörler (watched folders), iCloud Drive klasörleri dahil (dataless dosya indirme desteğiyle).
- whisper.cpp + large-v3-turbo + Silero VAD v6.2.0, dil: otomatik veya seçilen.
- Batch: çok kaynak → tek birleşik TXT. Tek kaynak → başlık adlı TXT.
- SQLite durum, crash recovery, otomatik temizlik, uyku engelleme.
- Menü çubuğu ikonu; pencere kapanınca iş arka planda sürer.
- ToolManager: yt-dlp ve Deno'yu indirir, doğrular, günceller.
- ModelManager: modeli indirir, doğrular.
- Sparkle 2 ile uygulama güncellemesi, Developer ID imza + notarization.

**v1.1 (şimdi yapma, ama mimari engellemesin)**
- Voice Memos Share Extension; Voice Memos Group Container otomatik izleme (experimental, Full Disk Access).
- SRT/VTT/JSON çıktı, RSS/podcast kaynakları, FFmpeg fallback, Apple SpeechAnalyzer motoru, Core ML encoder.

**Kapsam dışı**
- Windows/Linux/iOS, bulut transkripsiyon, LLM özetleme, konuşmacı ayrımı (diarization), çeviri, hesap/abonelik, YouTube kanal/oynatma listesi otomatik takibi, Mac App Store, Intel Mac.

### 3. Kesin teknoloji kararları

| Konu | Karar |
| --- | --- |
| Dil / UI | Swift 6, SwiftUI; gerektiğinde AppKit (NSPasteboard, NSStatusItem, NSApp activation policy) |
| Dağıtım | Developer ID imzalı, Hardened Runtime, notarize edilmiş DMG. App Sandbox **kapalı**. |
| Transkripsiyon | whisper.cpp resmi `whisper.xcframework` (sabit sürüm, ör. v1.8.3 veya testten geçen son sürüm), Metal açık, Core ML kapalı |
| Model | `ggml-large-v3-turbo.bin` (f16, 1,62 GB) RAM ≥ 16 GB ise; `ggml-large-v3-turbo-q5_0.bin` (574 MB) RAM < 16 GB ise. VAD: `ggml-silero-v6.2.0.bin`. Kaynak: Hugging Face `ggerganov/whisper.cpp` ve `ggml-org/whisper-vad`. SHA-256 değerleri kodda sabit. |
| Ses çözme | AVFoundation (`AVAudioFile` / `AVAssetReader`) → 16 kHz mono Float32 PCM, bellekte. FFmpeg yok. |
| YouTube | Resmi `yt-dlp_macos` executable'ı + Deno, ToolManager ile `~/Library/Application Support/<bundle-id>/Tools/` altına indirilir. Process ile çağrılır. |
| Veritabanı | SQLite, GRDB.swift, WAL modu, `DatabaseMigrator` |
| Log | `os.Logger` (subsystem = bundle id) + dönen dosya log (`Logs/app.log`, 5 MB × 3) |
| Arka plan | Ayrı helper yok. Tek süreç; pencere kapanınca `NSApp.setActivationPolicy(.accessory)`. Login'de başlatma: `SMAppService.mainApp`. |
| Uyku | Batch aktifken `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason:)` |
| Güncelleme | Uygulama: Sparkle 2 (EdDSA). Araçlar: ToolManager. Model: ModelManager. |
| Bundle ID | `com.<geliştirici>.TranskriptHub` (yer tutucu; kullanıcıya sor) |

### 4. Modüller ve sorumluluklar

```
TranskriptHub (Xcode app target)
├── App/            TranskriptHubApp, AppDelegate (menü çubuğu, activation policy), DependencyContainer
├── Features/       Capture, Processing, History, Settings, Onboarding (SwiftUI)
└── TranskriptHubCore (Swift package, UI yok)
    ├── Database/        AppDatabase (GRDB), migrations, kayıt tipleri
    ├── Jobs/            JobManager (actor, orkestratör), JobState, geçiş kuralları
    ├── Sources/         SourceInput, URLParser, YouTubeAdapter, LocalFileAdapter, FolderWatcher
    ├── Tools/           ToolManager (yt-dlp, Deno), YTDLPClient
    ├── Audio/           AudioDecoder (AVFoundation → PCM), AudioValidator
    ├── Transcription/   TranscriptionEngine (protokol), WhisperCppEngine, ModelManager, TranscriptPostProcessor
    ├── Batch/           BatchAssembler, OutputFormatter (Format-Version 1)
    ├── Output/          OutputWriter (atomik yazım, ad sanitizasyonu, çakışma)
    ├── Cleanup/         CleanupManager
    ├── System/          SleepGuard, DiskSpaceChecker, ClipboardMonitor, Notifications
    └── Logging/         Log, DiagnosticsExporter
```

Ana protokoller:

```swift
protocol SourceAdapter: Sendable {
    func canHandle(_ input: SourceInput) -> Bool
    func resolve(_ input: SourceInput) async throws -> ResolvedSource      // metadata
}

protocol MediaFetcher: Sendable {
    func fetch(_ source: ResolvedSource, into workspace: URL,
               progress: @Sendable (Double) -> Void) async throws -> URL   // yerel ses dosyası
}

protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: PreparedAudio, options: TranscriptionOptions,
                    progress: @Sendable (Double) -> Void) async throws -> TranscriptResult
}

struct TranscriptionOptions: Sendable {
    var language: String?        // nil = auto
    var useVAD: Bool             // varsayılan true
    var threads: Int             // varsayılan: performans çekirdeği sayısı
    var initialPrompt: String?   // isteğe bağlı terim listesi
}

struct TranscriptResult: Sendable {
    var segments: [Segment]      // start, end (saniye), text
    var detectedLanguage: String?
}
```

### 5. Veri modeli (SQLite)

```sql
CREATE TABLE batch (
  id              TEXT PRIMARY KEY,           -- UUID
  created_at      TEXT NOT NULL,              -- ISO-8601
  kind            TEXT NOT NULL,              -- 'youtube' | 'files' | 'mixed'
  expected_count  INTEGER NOT NULL,           -- oluşturulurken sabitlenir, sonradan hesaplanmaz
  state           TEXT NOT NULL,              -- active | assembling | completed | completedWithErrors | cancelled
  language        TEXT,                       -- NULL = auto
  output_path     TEXT,
  cleaned_at      TEXT
);

CREATE TABLE job (
  id              TEXT PRIMARY KEY,           -- UUID
  batch_id        TEXT NOT NULL REFERENCES batch(id) ON DELETE CASCADE,
  sequence        INTEGER NOT NULL,           -- 1..N, kullanıcının gördüğü sıra
  source_type     TEXT NOT NULL,              -- youtube | localFile | watchedFolder
  source_url      TEXT,
  source_path     TEXT,
  external_id     TEXT,                       -- YouTube video id
  title           TEXT,
  creator         TEXT,
  duration_sec    REAL,
  state           TEXT NOT NULL,
  attempt         INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  error_kind      TEXT,
  error_message   TEXT,
  workspace_path  TEXT,
  detected_lang   TEXT,
  updated_at      TEXT NOT NULL,
  UNIQUE(batch_id, sequence),
  UNIQUE(batch_id, external_id)
);

CREATE TABLE transcript_section (
  job_id     TEXT PRIMARY KEY REFERENCES job(id) ON DELETE CASCADE,
  text       TEXT NOT NULL,                   -- post-process edilmiş paragraflı metin
  segments   TEXT                             -- JSON (zaman damgaları için)
);

CREATE TABLE session_item (                   -- pano/yapıştırma ile toplanan, henüz gönderilmemiş linkler
  id          TEXT PRIMARY KEY,
  position    INTEGER NOT NULL,
  url         TEXT NOT NULL,
  external_id TEXT NOT NULL UNIQUE,
  title       TEXT,
  duration_sec REAL,
  added_at    TEXT NOT NULL
);

CREATE TABLE history (                         -- medya içermeyen hafif geçmiş, ayarla kapatılabilir
  external_id TEXT PRIMARY KEY,
  title       TEXT,
  output_path TEXT,
  done_at     TEXT NOT NULL
);

CREATE TABLE watched_folder (
  id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, enabled INTEGER NOT NULL,
  extensions TEXT NOT NULL, delete_original INTEGER NOT NULL DEFAULT 0
);
```

### 6. Job durum makinesi

Durumlar: `queued → fetching → fetched → transcribing → transcribed → completed`; hata yolu: `retryWaiting`, `failed`; kullanıcı: `cancelled`.

Kurallar:
- Geçişler yalnız `JobManager` actor'ü içinde ve DB transaction'ı ile yapılır. İzin verilmeyen geçiş = programlama hatası (assert + log).
- `fetched`: ses dosyası workspace'te ve doğrulanmış. `transcribed`: `transcript_section` satırı yazılmış.
- Terminal durumlar: `completed`, `failed`, `cancelled`.
- Batch, tüm job'ları terminal olduğunda `assembling` olur → final dosya yazılır → `completed` (hiç failed yoksa) veya `completedWithErrors`.
- Her aşamanın zaman aşımı var (§12). Aşılırsa hata = `timeout`, retry tablosuna göre.

Recovery (uygulama başlarken, UI'dan önce):
- `fetching` → workspace'teki yarım dosyayı sil, `queued`.
- `fetched` → olduğu gibi kalır (yeniden indirilmez).
- `transcribing` → `fetched` (transkripsiyon baştan; kısmi sonuç tutulmaz).
- `transcribed` → olduğu gibi kalır.
- `assembling` batch → yeniden assemble.
- DB'de olmayan workspace klasörleri ve `.partial` dosyaları → sil.

### 7. İşlem hattı ve eşzamanlılık

```
[queued] --(FetchQueue, max 2 paralel YouTube / 4 yerel)--> [fetched]
[fetched] --(TranscribeQueue, tek seferde 1)--> [transcribed]
tüm job'lar terminal --> BatchAssembler --> OutputWriter --> CleanupManager
```

- İndirme ve transkripsiyon birbirini beklemez: video 1 transkript edilirken video 2–3 iner (Buzz'a "hepsini bırak" davranışının native karşılığı).
- TranscribeQueue sırası: önce `sequence` küçük olan, batch'ler arasında FIFO.
- whisper context'i bir kez yüklenir ve batch boyunca yeniden kullanılır; 10 dk boşta kalırsa bellekten atılır.
- YouTube istekleri arasında 1–3 sn rastgele bekleme.
- Yeni batch, aktif batch sürerken eklenebilir; kuyruğa girer.

### 8. Modül detayları

**8.1 URLParser**
- `URLComponents` kullan, regex değil. Kabul edilen hostlar: `youtube.com`, `www.youtube.com`, `m.youtube.com`, `music.youtube.com`, `youtu.be`, `www.youtube-nocookie.com`.
- Yollar: `/watch?v=ID`, `youtu.be/ID`, `/shorts/ID`, `/live/ID`, `/embed/ID`. ID = tam 11 karakter `[A-Za-z0-9_-]`.
- `list=` parametresi yok sayılır (oynatma listesi genişletme v1'de yok); `t=` yok sayılır.
- Kanonik URL: `https://www.youtube.com/watch?v=ID`.
- Bir metin içinde birden fazla link varsa hepsini çıkar (çoklu yapıştırma).
- Unit test: en az 25 geçerli + 15 geçersiz örnek (alan adı taklidi `youtube.com.evil.com`, 10/12 karakter ID, boş, `?v=` başka sitede vb.).

**8.2 ClipboardMonitor**
- Yalnız ana pencere açıkken ve "Yakalama" anahtarı açıkken çalışır; 0,75 sn'de bir `NSPasteboard.general.changeCount` kontrol eder.
- Değişiklik varsa: tür listesinde `org.nspasteboard.ConcealedType` veya `org.nspasteboard.TransientType` varsa hiç okuma (şifre yöneticileri).
- macOS 15.4+ ise önce `detect` API'si ile URL olasılığına bak; yoksa okuma. Varsa `string(forType: .string)` oku.
- `accessBehavior` "her zaman reddet" ise yakalama alanında açıklama + "Sistem Ayarlarını Aç" butonu göster.
- Bulunan her geçerli ID `session_item`'a eklenir (aynı ID ikinci kez eklenmez, kısa "zaten listede" bildirimi). Liste uygulama kapanıp açılsa da korunur.
- Eklenen link için arka planda hafif metadata çekilir (başlık, süre) ve listede gösterilir; başarısızsa link yine eklenir, başlık "Bilinmiyor".

**8.3 ToolManager**
- Yönetilen araçlar: `yt-dlp` (GitHub `yt-dlp/yt-dlp` releases, `yt-dlp_macos` dosyası, doğrulama: aynı release'teki `SHA2-256SUMS`) ve `deno` (GitHub `denoland/deno` releases, `deno-aarch64-apple-darwin.zip`, release'teki `.sha256sum` dosyası). Yükleme yeri: `Tools/<araç>/<sürüm>/`, aktif sürüm `Tools/<araç>/current` sembolik linki.
- İlk açılışta (onboarding) indirilir. Sonra: uygulama açılışında en fazla günde 1 kez sürüm kontrolü; yeni sürüm varsa sessizce indir, doğrula, `current`'ı atomik değiştir, eski sürümün 1 tanesini geri dönüş için sakla.
- yt-dlp çağrısı `--js-runtimes deno:<deno yolu>` ile yapılır (yt-dlp'nin resmi EJS dokümantasyonuna göre; sürüm değişirse güncel bayrağı kontrol et).
- YouTube çıkarma hatası (`extractorError`, "Sign in to confirm", 403) alındığında: son 6 saatte güncelleme kontrolü yapılmadıysa hemen güncelle, sonra job'u 1 kez tekrar dene.
- Settings'te: araç sürümleri, son kontrol, "Şimdi güncelle", "Önceki sürüme dön".
- İndirme kaynakları ve doğrulama yöntemi kodda tek yerde tanımlı olsun (gelecekte değiştirilebilir).

**8.4 YTDLPClient (YouTube fetch)**
- Tek çağrı, metadata + indirme birlikte:

```text
yt-dlp --no-playlist --newline --socket-timeout 30 --retries 3 \
  -f "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/18" \
  -o "<workspace>/input.%(ext)s" \
  --no-simulate --print "%(.{id,title,channel,duration,ext})#j" \
  --progress --progress-template "download:%(progress._percent_str)s" \
  --js-runtimes deno:<deno yolu> <url>
```

- stdout satırları ayrıştırılır: JSON satırı = metadata, yüzde satırları = ilerleme. stderr log'a yazılır (URL'ler log'da kalabilir, transcript asla). Bayrak kombinasyonu M2'de gerçek çıktıyla doğrulanır.
- Format 18 seçilirse (mp4 video+ses) AVFoundation ses izini okur; ek dönüşüm yok.
- Süreç zaman aşımı: 15 dk veya (süre × 0,5), hangisi büyükse; aşılırsa süreci SIGTERM, 5 sn sonra SIGKILL.
- Çıkış kodu + stderr içeriğine göre hata sınıflandır: `videoUnavailable` (private/silinmiş), `ageRestricted`, `botCheck`, `network`, `noAudioFormat`, `unknown`.
- Ayarlarda gelişmiş seçenek: "IPv4 zorla" (`-4`).

**8.5 LocalFileAdapter ve FolderWatcher**
- Sürükle-bırak/seçilen dosya workspace'e **kopyalanır** (APFS'te `clonefile` ile anında). Orijinal salt okunur.
- FolderWatcher: FSEvents (`FSEventStreamCreate`, file-level events). Uygulama açılışında da klasör bir kez taranır (kaçan olaylar için).
- Yeni dosya kabul kuralları (legacy iCloud scriptinin native karşılığı):
  1. Uzantı izin listesinde mi (varsayılan: m4a, mp3, wav, aac, caf, aiff, mp4, mov)?
  2. Gizli dosya, `.part`, `.download`, `.icloud` ise atla.
  3. iCloud dataless ise (`URLResourceValues.ubiquitousItemDownloadingStatus != .current`) → `FileManager.startDownloadingUbiquitousItem(at:)` çağır, tamamlanınca tekrar değerlendir.
  4. Boyut stabil mi: 2 ölçüm arası 3 sn, boyut aynı ve > 0.
  5. Workspace'e kopyala (`input.<ext>.partial` → rename).
  6. `AudioValidator` ile aç: ses izi var mı, süre > 1 sn mi.
  7. Job oluştur. Aynı dosya (yol + boyut + değişiklik tarihi) için ikinci job açma.
- İzlenen klasördeki her dosya tek kaynaklı batch olur ve kendi adıyla TXT üretir. Eşleştirme her zaman job ID ile, asla dosya adı önekiyle.
- "Başarılı transkriptten sonra orijinali sil" ayarı klasör başına, varsayılan **kapalı**. Açıksa silme yalnız final TXT doğrulandıktan ve boş olmadığı kontrol edildikten sonra, dosyayı Çöp Kutusu'na taşıyarak (`FileManager.trashItem`), kalıcı silme değil.

**8.6 AudioDecoder**
- Girdi: workspace'teki dosya. Çıktı: `PreparedAudio { samples: [Float] (16 kHz mono), duration }`.
- `AVAudioFile` + `AVAudioConverter` ile 16 kHz mono Float32'ye çevir. Çözülemezse `unsupportedMedia`.
- 3 saati aşan seslerde 30 dk'lık parçalar halinde ver (2 sn örtüşme yok; VAD sınırları yeterli) ve `TranscriptResult`'ları zaman ofsetiyle birleştir.

**8.7 WhisperCppEngine**
- `whisper_init_from_file_with_params` (use_gpu = true), parametreler: `WHISPER_SAMPLING_GREEDY` yerine beam search 5 (Buzz/CLI varsayılanına yakın kalite için; Milestone 1'de iki seçenek ölçülüp karar verilir), `language` = seçilen veya `"auto"`, `translate = false`, `no_timestamps = false`, `print_*` = false, VAD açık + `vad_model_path`, thread sayısı = performans çekirdeği sayısı.
- `progress_callback` ile yüzde, `abort_callback` ile iptal desteği.
- Context tek bir actor içinde; aynı anda tek transkripsiyon.
- Çıktı segmentleri `TranscriptPostProcessor`'a gider.

**8.8 TranscriptPostProcessor**
- Baş/son boşlukları temizle, `[BLANK_AUDIO]`, `[Music]`, `(müzik)` gibi etiket satırlarını kaldır (ayarla kapatılabilir).
- Tekrar döngüsü tespiti: aynı normalize edilmiş segment metni art arda ≥ 3 kez geliyorsa ilkini tut, diğerlerini at ve log'a uyarı yaz.
- Paragraflama: segmentler arasında ≥ 1,5 sn sessizlik veya paragraf ~600 karakteri geçtiyse ve segment cümle sonu ile bitiyorsa yeni paragraf.
- İsteğe bağlı: her paragrafın başına `[HH:MM:SS]` (ayar, varsayılan kapalı).

**8.9 BatchAssembler + OutputFormatter**
- Bölümler `ORDER BY sequence`. Başarısız job'lar da bölüm olarak yer alır.
- Format kesin olarak §9'daki gibi.

**8.10 OutputWriter**
- Çıktı klasörü varsayılan: `~/Library/Mobile Documents/com~apple~CloudDocs/Transkript/` (yoksa oluştur; iCloud Drive kapalıysa `~/Documents/Transkript/`). Ayarlardan değiştirilebilir.
- Dosya adı: tek kaynak → `<başlık>.txt`; çoklu → `YouTube - <N> Video - <YYYY-MM-DD>.txt` (yerel dosya batch'inde `Ses - <N> Dosya - <YYYY-MM-DD>.txt`).
- Sanitizasyon: `/ : \ * ? " < > |` ve kontrol karakterleri → `-`; baş/son boşluk ve nokta temizlenir; ardışık boşluk teke iner; en fazla 150 karakter (uzantı hariç, Unicode grapheme bazlı kesim); boşsa `Transkript`.
- Çakışma: dosya varsa ` (2)`, ` (3)`… eki; **asla üzerine yazma** (yeniden üretim hariç: aynı batch'in "tekrar dene" sonrası kendi dosyası değiştirilir).
- Atomik yazım: aynı klasörde `.<ad>.partial` → `FileHandle.synchronize()` → geri oku ve uzunluk/UTF-8 doğrula → `rename`. Encoding UTF-8 (BOM yok), satır sonu `\n`.
- Yazım hatası (`outputWriteFailure`): dosya Application Support'taki `Outbox/` klasörüne yazılır, kullanıcıya bildirim ve "Kaydet…" seçeneği; temizlik yapılmaz.

**8.11 CleanupManager**
- Sıra (değiştirilemez): final yazıldı ve doğrulandı → DB'de batch `completed`/`completedWithErrors` → job workspace klasörleri silinir → `transcript_section` satırları silinir (ayar "geçmişte metni tut" kapalıysa) → batch `cleaned_at` set.
- Başarısız job'ların workspace'i de silinir (ses tutulmaz) ama `job` satırı hata bilgisiyle 7 gün kalır (Retry için yeniden indirir).
- Uygulama açılışında: 7 günden eski terminal batch'ler ve job'lar silinir; sahipsiz workspace'ler silinir.
- Hedef: başarılı batch sonrası `Jobs/` klasörü boş.

**8.12 SleepGuard, DiskSpaceChecker, Notifications**
- SleepGuard: aktif job varken activity açık, kuyruk boşalınca kapanır.
- DiskSpaceChecker: indirme öncesi `volumeAvailableCapacityForImportantUsage` ≥ tahmini boyut (yoksa süre × 1 MB/dk) + 1 GB; değilse job `retryWaiting` (insufficientDiskSpace) + bildirim.
- Bildirimler (UserNotifications): batch bitti (dosyayı aç aksiyonu), batch hatalarla bitti, araç güncellemesi başarısız, bot tespiti nedeniyle duraklatıldı.

### 9. Çıktı formatı (Format-Version 1)

Çoklu batch:

```
TRANSKRIPT HUB EXPORT
Format-Version: 1
Batch-ID: 2C5E…-UUID
Source-Type: YouTube
Created: 2026-10-03 21:03:02
Item-Count: 5
Completed: 4
Failed: 1
Model: large-v3-turbo (f16), VAD: on, Language: auto

====================================================================
VIDEO 1 / 5
====================================================================
TITLE: …
CHANNEL: …
DURATION: 15:14
URL: https://www.youtube.com/watch?v=…
LANGUAGE: tr

TRANSCRIPT

<paragraflar, aralarında boş satır>

====================================================================
VIDEO 2 / 5
====================================================================
TITLE: …
URL: …
STATUS: İŞLENEMEDİ — Video kullanılamıyor (silinmiş veya gizli)
```

- Tek kaynakta da aynı başlık bloğu + tek bölüm kullanılır (dosya adı başlıktır).
- Yerel dosyada `VIDEO` yerine `ITEM`, `CHANNEL/URL` yerine `FILE: <orijinal ad>`.
- Legacy fixture'daki `VIDEO x / N` düzeni korunur; regresyon testi bunu kontrol eder.

### 10. Dosya sistemi yerleşimi

```
~/Library/Application Support/<bundle-id>/
├── Database/jobs.sqlite (+ -wal, -shm)
├── Models/ggml-large-v3-turbo.bin, ggml-silero-v6.2.0.bin
├── Tools/yt-dlp/<sürüm>/, Tools/deno/<sürüm>/, current linkleri
├── Jobs/<job-uuid>/input.m4a (yalnız işlem sırasında)
├── Outbox/ (yalnız çıktı klasörü yazılamazsa)
└── Logs/app.log
```

- Teknik durum asla iCloud'a yazılmaz. iCloud'a yalnız final TXT gider.

### 11. Kullanıcı arayüzü

**Ana pencere (tek pencere, iki sekme: "Linkler" ve "Dosyalar")**
- Linkler: üstte yakalama anahtarı ("Panoyu izle", açık/kapalı göstergesi) + çok satırlı yapıştırma alanı. Altta oturum listesi: sıra no, başlık, kanal, süre, kaldır butonu, sürükle-bırak ile yeniden sıralama. Altta: dil seçimi (Otomatik / Türkçe / Almanca / İngilizce / diğer…), "Listeyi temizle", birincil buton "N videoyu transkript et".
- Dosyalar: büyük bırakma alanı + "Dosya seç". Bırakılan dosyalar hemen tek tek job olur (ayar: "birden fazla dosyayı tek TXT'de birleştir", varsayılan kapalı).
- Alt şeritte işlem durumu: aktif batch'ler, her job için durum + ilerleme yüzdesi, tahmini kalan süre (son 3 job'un gerçek zamanlı oranından).
- "Gönder" sonrası davranış (ayar): Pencereyi kapat ve arka planda devam et (varsayılan) / Pencereyi açık tut. Ek ayar: "Kuyruk bitince uygulamadan çık" (varsayılan açık: legacy davranış "worker kapandı").

**Menü çubuğu**
- İkon: boşta sade, iş varken ilerleme göstergesi. Menü: aktif batch özeti, "Pencereyi aç", "Duraklat/Devam", son 5 çıktı (tıkla = aç), "Çık" (iş varsa onay: "Devam eden işler kaydedildi, sonra devam eder").

**Geçmiş**
- Son batch'ler: tarih, öğe sayısı, durum, "Aç", "Finder'da göster", hatalı batch'te "Başarısızları tekrar dene".

**Onboarding (ilk açılış, 4 adım)**
1. Kısa tanıtım + kullanım koşulu onayı: "Yalnız indirme ve transkripsiyon hakkın olan içerikleri işle."
2. Çıktı klasörü seçimi (varsayılan iCloud Drive/Transkript).
3. Model + araç indirme (ilerleme çubuğu, toplam boyut gösterilir; RAM'e göre model önerisi, değiştirilebilir).
4. Bildirim izni. (Pano izni macOS sorduğunda kullanıcıya ne seçmesi gerektiğini anlatan kısa not.)

**Ayarlar**
- Genel: çıktı klasörü, gönder sonrası davranış, kuyruk bitince çık, login'de başlat.
- Transkripsiyon: model (f16 / q8_0 / q5_0), varsayılan dil, VAD, zaman damgaları, müzik/etiket satırlarını kaldır, başlangıç ipucu (terim listesi).
- YouTube: paralel indirme (1–3, varsayılan 2), IPv4 zorla, aynı video başka batch'te: Sor / İzin ver / Atla (varsayılan Sor).
- Kaynaklar: izlenen klasörler listesi (ekle/kaldır/aç-kapa, uzantılar, orijinali çöpe taşı).
- Gizlilik ve temizlik: geçmişi tut (açık), transkript metnini geçmişte tut (kapalı), "Tüm geçici verileri şimdi temizle".
- Araçlar ve modeller: sürümler, güncelle, geri dön, disk kullanımı.
- Tanılama: "Tanılama paketi oluştur" (log + hata özetleri + sistem bilgisi; transcript metni ve URL'ler maskelenmiş).

### 12. Hata modeli ve yeniden deneme

| error_kind | Örnek | Yeniden deneme | Kullanıcıya |
| --- | --- | --- | --- |
| invalidURL | YouTube olmayan link | Yok | Listeye hiç eklenmez |
| videoUnavailable | Silinmiş/gizli video | Yok | TXT'de "İŞLENEMEDİ" |
| ageRestricted | Yaş kısıtlı | Yok | TXT'de "İŞLENEMEDİ — yaş kısıtlı" |
| botCheck | "Sign in to confirm…", 429 | Araç güncelle → 1 deneme; tekrar olursa tüm YouTube indirmeleri 10 dk duraklat, sonra 1 deneme | Bildirim |
| network | Zaman aşımı, bağlantı yok | 3 deneme: 5 sn, 30 sn, 2 dk | Gerekirse bildirim |
| noAudioFormat | Uygun ses formatı yok | Yok | TXT'de |
| unsupportedMedia | AVFoundation açamıyor | Yok | Dosya için bildirim |
| insufficientDiskSpace | — | Yer açılınca, 5 dk aralıkla kontrol | Bildirim |
| modelUnavailable | Model eksik/bozuk | ModelManager yeniden indirir → 1 deneme | Bildirim |
| transcriptionFailure | whisper hata kodu | 1 deneme | TXT'de |
| timeout | Aşama süresi aşıldı | 1 deneme | TXT'de |
| outputWriteFailure | Klasör yok/izin yok | Outbox'a yaz | Bildirim + "Kaydet…" |

Zaman aşımları: indirme §8.4; transkripsiyon = max(10 dk, ses süresi × 2); assemble = 2 dk.

### 13. İzinler, imza, Info.plist

- Hardened Runtime açık. Entitlement gerekmez (sandbox yok, JIT yok; Deno ayrı süreç ve bundle dışında).
- Info.plist: `LSMinimumSystemVersion` 14.0, `LSApplicationCategoryType` productivity, gerekli `NS…UsageDescription` metinleri (Masaüstü/Belgeler/İndirilenler klasörleri için; izlenen klasör eklenirken macOS sorabilir).
- `LSUIElement` kullanma; activation policy runtime'da değişir.
- ToolManager'ın indirdiği dosyalar uygulamanın kendisi tarafından yazıldığı için quarantine almaz; yine de çalıştırmadan önce `com.apple.quarantine` xattr'ı varsa kaldır ve SHA-256'yı her güncellemede doğrula.
- Release pipeline: `xcodebuild archive` → Developer ID ile imza (xcframework dahil) → `notarytool submit --wait` → `stapler staple` → DMG (imzalı + notarize) → Sparkle appcast.

### 14. Gizlilik

- Ses ve transcript hiçbir sunucuya gönderilmez. Ağ yalnız: YouTube indirme, model indirme, araç/uygulama güncelleme kontrolü.
- Analytics yok, telemetri yok.
- Log'lara transcript metni asla yazılmaz. Başlık ve URL log'da olabilir; tanılama paketinde maskelenir.

### 15. Test planı

**Unit (Core, ağsız)**
- URLParser (≥ 40 örnek), dosya adı sanitizasyonu ve çakışma, OutputFormatter (legacy 5-video fixture ile birebir başlık/bölüm düzeni), durum geçiş tablosu (izinli/izinsiz tüm geçişler), recovery kuralları, TranscriptPostProcessor (tekrar döngüsü, paragraflama), CleanupManager sırası, retry/backoff hesapları, yt-dlp stdout/stderr ayrıştırma ve hata sınıflandırma (kaydedilmiş gerçek çıktı örnekleriyle).

**Entegrasyon (fixture dosyalarıyla)**
- Sahte `MediaFetcher` (yerel HTTP veya dosya kopyası) ile 1, 5, 20, 50 öğelik batch; sıra 1…50 doğru, tek TXT, workspace boş.
- Gerçek whisper ile: 30 sn Türkçe, 30 sn Almanca, 30 sn İngilizce, 2 dk sessizlik + konuşma, 10 sn müzik (halüsinasyon kontrolü).
- Arıza enjeksiyonu: indirme ortasında süreç öldürme, transkripsiyon ortasında uygulamayı öldürme (recovery), disk dolu simülasyonu, çıktı klasörü silinmiş, model dosyası bozuk (SHA uyuşmazlığı), aynı video iki kez, 20 videodan 1'i başarısız.

**Manuel (gerçek YouTube, CI'da değil)**
- 1, 5, 20 video; uyku/uyanma sırasında batch; yeniden başlatma sonrası devam; iCloud dataless dosya.

### 16. Milestone'lar ve kabul kriterleri

**M0 — Referansı dondur (kod yok)**
- Golden Snapshot (düzeltilmiş sürüm) alınır, repo `docs/legacy-reference/` altına konur, 5-video ve tek video çıktıları `Tests/Fixtures/` altına.
- Kabul: snapshot'taki finalizer kaynak kodu tam; SHA-256 manifest var.

**M1 — Buzz'sız ilk transcript (CLI)**
- `transkripthub-cli transcribe sample.m4a` → `sample.txt`. ModelManager + AudioDecoder + WhisperCppEngine + PostProcessor.
- Kabul: aynı 3 test dosyasında Buzz çıktısına göre kelime hata farkı ≤ %2 puan; işlem süresi Buzz'ın ≤ 1,1 katı; tepe bellek f16'da ≤ 4 GB; greedy vs beam karşılaştırması belgelendi.

**M2 — YouTube tek video (CLI)**
- ToolManager + YTDLPClient + OutputWriter. `transkripthub-cli youtube <url>` → `Başlık.txt`, workspace boş.
- Kabul: 10 farklı gerçek videoda (shorts, live arşiv, uzun 1 saat+ dahil) başarı; silinmiş video doğru hata; araç güncelleme ve geri dönüş çalışıyor.

**M3 — Batch + DB + recovery (CLI)**
- GRDB şeması, JobManager, kuyruklar, BatchAssembler, CleanupManager, recovery.
- Kabul: 20 linklik batch tek TXT, sıra doğru; ortasında süreç öldürülüp yeniden başlatılınca indirilmiş videolar yeniden inmiyor; 1 bozuk link ile `completedWithErrors` ve TXT'de işaret; sonunda `Jobs/` boş.

**M4 — SwiftUI uygulama**
- Ana pencere, pano yakalama, oturum listesi, işlem görünümü, menü çubuğu, gönder sonrası arka plan, onboarding, ayarlar, bildirimler, SleepGuard.
- Kabul: legacy AppleScript uygulamasının tüm davranışları karşılanıyor (link biriktirme, liste kalıcılığı, gönder → pencere kapanır → iş sürer → bitince çıkar).

**M5 — Dosyalar ve izlenen klasörler**
- Sürükle-bırak, FolderWatcher, iCloud dataless, stabilite, orijinali çöpe taşıma ayarı.
- Kabul: iPhone'dan iCloud Drive'daki izlenen klasöre bırakılan ses Mac'te otomatik TXT olur; "Memo 1 / Memo 10" adlı dosyalarda yanlış silme yok.

**M6 — Yayın**
- İmza, notarization, DMG, Sparkle, tanılama paketi, README, THIRD_PARTY_NOTICES (whisper.cpp MIT, GRDB MIT, Sparkle MIT, yt-dlp Unlicense + yt-dlp_macos içindeki bileşenlerin lisansları, Deno MIT, model lisansları).
- Kabul ("Done" tanımı): temiz bir Mac'te DMG → Applications → aç → onboarding → 20 YouTube linki → pencere kapat → hepsi arka planda iner ve transkript edilir → tek TXT → geçici dosya yok → uygulama kendini kapatır → ortada yeniden başlatma yapılırsa kaldığı yerden devam eder → izlenen klasöre bırakılan ses TXT olur → Terminal hiç açılmadı.

### 17. Yapma listesi

- Buzz, Homebrew, sistem Python'u veya `/opt/homebrew` yollarına bağımlılık.
- Shell script çağırarak iş yapmak (yalnız yt-dlp ve Deno süreçleri çağrılır).
- Dosya adına durum kodlamak; durum yalnız DB'de.
- iCloud'a teknik dosya yazmak.
- Kullanıcının orijinal dosyasını kalıcı silmek; Voice Memos klasöründe herhangi bir değişiklik yapmak.
- Transcript metnini log'a yazmak.
- Final yazılıp doğrulanmadan geçici sesi silmek.
- Birden fazla whisper context'ini aynı anda yüklemek.
- YouTube kanallarını/oynatma listelerini otomatik takip etmek.
- Bu spesifikasyonda olmayan bir bağımlılık eklemek veya mimariyi değiştirmek (önce sor).

### 18. Açık sorular (geliştirmeye başlamadan kullanıcıya sorulacak)

1. Bundle ID ve geliştirici adı ne olacak? Apple Developer Program üyeliği var mı (Developer ID + notarization için gerekli)?
2. v1 yalnız kişisel kullanım mı, yoksa başkalarına da dağıtılacak mı? (Dağıtılacaksa §13 ve lisans kontrolü zorunlu.)
3. Tek video çıktısının adı başlık mı kalsın, yoksa `YouTube - Başlık - Tarih` gibi tutarlı bir şema mı?
4. Mevcut Voice Memos akışında ses dosyaları iCloud'daki hangi klasöre geliyor (iPhone Kestirmesi mi)? Bu klasör M5'te varsayılan izlenen klasör yapılacak.
