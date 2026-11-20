# Transkript Hub 🎙️⚡

<p align="center">
  <a href="https://github.com/Akifulutas/Transkript-Hub/releases/latest/download/TranskriptHub.dmg">
    <img src="https://img.shields.io/badge/📥_Download_Transkript_Hub-macOS_(Apple_Silicon)-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download Transkript Hub for macOS">
  </a>
  <br>
  <sub>⚡ Tek tıkla indirin • Apple Silicon (M1/M2/M3/M4) • Sıfır Python / Harici Bağımlılık • %100 Çevrimdışı Maksimum Doğruluk</sub>
</p>

**Apple Silicon Mac'ler için %100 Yerel, Çevrimdışı, Maksimum Doğruluk Odaklı Ses ve Video Transkripsiyon Stüdyosu.**

Transkript Hub; yerel ses ve video kayıtlarını (Voice Memos, M4A, MP3, WAV, AAC, FLAC, OGG, Opus, WMA, MP4, MOV, MKV, WebM) ve YouTube içeriklerini (tekil video, oynatma listesi, kanal) harici sunuculara tek bir bayt veri göndermeden, doğrudan Mac'inizin Apple Silicon donanımı (**Metal GPU + Apple Accelerate BLAS / vDSP**) üzerinde metne (`.txt`) ve SubRip (`.srt`) altyazısına dönüştürür.

---

## ✨ Özellikler (Features)

- **👑 Çift Motorlu Maksimum Doğruluk Mimarisi:**
  - **`WhisperCppEngine` (`whisper.xcframework` Metal GPU + `flash_attn` + `Beam Search 5`):** Tam 32 katmanlı **`Large-v3` (FP16)** ve **`Large-v3 (Q5_0)`** modelleriyle Almanca, Türkçe ve İngilizce konuşmalarda en yüksek doğal dil ve teknik terim doğruluğu.
  - **`Qwen3ASREngine` (Saf C `CQwenASR` + Apple `Accelerate` BLAS / NEON):** Sıfır Python/PyTorch bağımlılığıyla doğrudan C üzerinden çalışan **`Qwen3-ASR-1.7B`** motoru; sıfır tekrar döngüsü ve konuşulan yazılım/dosya yollarını (`examples/source/.../machine_data_library.py`, `C++`, `Sink Modul`) doğrudan geliştirici sözdizimiyle yazma uzmanlığı.
- **🛡️ Nöral Silero VAD v6.2.0 + Saf Swift `vDSP` Akustik Ön İşleme:**
  - **95 Hz Butterworth Yüksek Geçiren Filtre & Kısık-Ses Kazancı (`AudioConditioner`):** Masa/mikrofon darbelerini ve alt frekans uğultularını temizler; yalnızca gerçekten kısık (`p90 < -32 dBFS`) ve konuşma modülasyonu taşıyan (`p90 > p15 * 1.8`) kayıtlara `+12 dB`'e kadar yumuşak sınırlamalı (`tanh`) doğrusal kazanç uygular.
  - **Nöral Konuşma Tespiti (`SileroVAD v6.2.0`):** Gömülü `864 KB` Silero LSTM modeliyle sessizlik tuzaklarında yanlış pozitif ve halüsinasyon oranını **`0/5 (0 kelime)`** düzeyine indirir, her konuşma kesitini `<= 28.0 sn` bağımsız dilimler halinde işler.
- **🧹 3 Katmanlı Cerrahi Post-Processing (`TranscriptPostProcessor`):**
  - Sessizlik/jenerik halüsinasyonlarını (`"es heilt die göttliche Kraft"`, `"amara.org"`, `"Teksting av Nicolai Winther"`, `"Hvað er það?"`), tek başına kalan outro kalıplarını (`"Vielen Dank"`, `"Amen"`) ve cümle içi / segmentler arası tekrar döngülerini gerçek teknik cümlelere zarar vermeden temizler.
- **🚫 Sıfır Harici Kurulum:** Python, PyTorch, MLX, Homebrew veya Terminal kurulumu gerektirmez. Tek bir `.dmg` indirin ve çalıştırın.
- **👁️ Gerçek Zamanlı Canlı Akış & Kelime Bazlı Ses Takibi:** Çözümlenen her segment canlı olarak ekrana akar; kelimelere tıklayarak ses kaydının tam o saniyesine (`±100 ms`) atlayabilirsiniz.
- **📁 Klasör İzleme, Sesli Notlar (Voice Memos) & iCloud Drive Senkronizasyonu:** İzlenen klasörlere veya Apple Sesli Notlar'a düşen kayıtları otomatik algılar, `.icloud` bulut dosyalarını indirip deşifre eder ve önbellek (`TranscriptCacheManager`) sayesinde aynı dosyayı iki kez işlemez.

---

## 🧠 Yapay Zeka Ajanları ve Geliştiriciler İçin Mimari Referans (AI Agent Pipeline & Parameter Rationale)

> **Bu Bölümün Amacı:** Bu bölüm, projeyi inceleyen veya iyileştirme önerisi sunacak olan başka yapay zeka ajanlarının (LLM / Coding Agents) **hangi modelin neden seçildiğini, hangi modelin neden elendiğini ve boru hattındaki (pipeline) her bir parametrenin hangi deneysel kanıtla o değere sabitlendiğini** tam olarak anlaması için yazılmıştır. Herhangi bir parametreyi değiştirmeden önce aşağıdaki deneysel bulguları ve **"Gelecek Yapay Zeka Ajanları İçin Kırmızı Çizgiler"** bölümünü okuyun.

---

### 1. Model Seçimi ve Budama Kararları (Neden Yalnızca 3 Model Bırakıldı?)

Temel tasarım ilkesi: **"Hız ikincildir; birincil ve tek hedef maksimum transkripsiyon doğruluğu, sıfır halüsinasyon ve teknik/çok dilli (Almanca + Türkçe + İngilizce) sadakattir."**

Apple M1 Pro (10 CPU çekirdeği, 16 GB birleşik bellek) üzerinde gerçek masaüstü kayıtlarından oluşan **12 test klibi** (`5` yoğun Almanca mühendislik/CAD/Python/SystemC ve Türkçe konuşma klibi = `750 sn`, `2` ek Türkçe/seyrek Almanca klip = toplam `910.23 sn` konuşma + `5` gerçek sessizlik/ortam gürültüsü tuzağı) ile **132 ardışık koşuluk** kıyaslama ve **3 kontrollü A/B deneyi** yürütülmüştür.

#### ✅ Katalogda Tutulan 3 Elit Model (`>= 1 GB` ve `>= 9.5/10` Doğruluk)

| Model (`WhisperModelCatalog`) | Boyut | Motor & Donanım | Uygulama İçi Skor (`Hız` / `Doğruluk`) | Ölçülen Gerçek Hız (M1 Pro) | Neden Tutuldu? (Spesifik Uzmanlık Alanı) |
| :--- | :---: | :--- | :---: | :---: | :--- |
| **`Large-v3`** (`ggml-large-v3.bin`) | **3.09 GB** | `WhisperCppEngine` (`whisper.xcframework` Metal GPU FP16 + `flash_attn`) | **6.8/10** Hız<br>**9.7/10** Doğruluk | `11.94x` ham / **`19.7x–21.6x`** (Silero VAD ile) | **#1 Genel ve Çok Dilli Doğruluk Şampiyonu (Varsayılan Model).** Tam 32 çözücü katmanı (FP16). Almanca CAD/motor mühendisliği terimlerinde **7/7** (`Notch, Kerbe, Luftpolster, Metall, Open Folder, Mindstorms, Klasse`), Python mimari terimlerinde **7/8**, Türkçe doğal konuşma morfolojisinde en yüksek sadakat. |
| **`Qwen3-ASR-1.7B`** (`qwen3-asr-1.7b/`) | **4.70 GB** | `Qwen3ASREngine` (Saf C `CQwenASR`, Apple `Accelerate` BLAS + NEON CPU, `-O3 -ffast-math`) | **5.0/10** Hız<br>**9.6/10** Doğruluk | `6.16x` yoğun / **`8.70x`** ortalama (CPU) | **#1 Sıfır Döngü & Yazılım / Dosya Yolu Uzmanı.** 132 koşuda **0 tekrar döngüsü (`loops=0`)** ve **0 Whisper kalıp halüsinasyonu**. Konuşulan Python dosya yollarını kelimelere bölmek yerine doğrudan geliştirici sözdizimiyle (`examples/source/machineauslagerung/design/libraries/machine_data_library.py`) ve donanım terimlerini (`Source Modul und ein Sink Modul`, `C++`) birebir doğru yazar. |
| **`Large-v3 (Q5_0)`** (`ggml-large-v3-q5_0.bin`) | **1.08 GB** | `WhisperCppEngine` (`whisper.xcframework` Metal GPU Q5_0 + `flash_attn`) | **6.0/10** Hız<br>**9.5/10** Doğruluk | `9.54x` ham (Metal Q5_0) | **#1 Kompakt 32-Katman Modeli.** Bellek kısıtlı senaryolarda 4 katmanlı `Turbo`'ya düşmek yerine tam **32 katmanlı** çözücü derinliğini `1.08 GB` boyutta korur; CAD teknik terim testinde FP16 ile aynı **7/7** skoru ve 12 klipte yalnızca `1` döngü üretti. |

#### ❌ Katalogdan Çıkarılan Modeller ve Çıkarılma Gerekçeleri

1. **`Tiny` (75 MB, `4.0/10`), `Base` (142 MB, `5.5/10`), `Small` (466 MB, `7.2/10`):** `< 1 GB` altındaki bu modeller teknik Almanca ve günlük Türkçe konuşmalarda ağır kelime/morfoloji kaybı yaşar. Doğruluk odaklı bir stüdyoda kullanıcıyı yanıltmamak için tamamen kaldırılmıştır.
2. **`Large-v3-Turbo (Q5_0)` (547 MB, `8.5/10`):** `< 1 GB` sınırının altındadır; ayrıca Apple Silicon Metal GPU'da niceleme çözme (dequantization) yükü nedeniyle FP16 `Turbo`'dan hem daha yavaş (`21.43x` vs `24.48x`) hem daha düşük doğrulukludur.
3. **`Medium` (1.5 GB, `8.2/10`):** **Tamamen Pareto-domine (mantıksız) bir modeldir.** `Large-v3 (Q5_0)` (`1.08 GB`, `9.5/10`) modelinden hem **daha büyük** (`1.5 GB` vs `1.08 GB`) hem de **çok daha düşük doğrulukludur** (`8.2/10` vs `9.5/10`).
4. **`Large-v3-Turbo` (1.6 GB FP16, `8.8/10`):** `Large-v3`'ün 32 çözücü katmanının **yalnızca hız uğruna 4 katmana budanmış (distilled)** halidir. Deneylerimizde 32→4 katman budamasının Almanca teknik bağlamda (`"spätestens die Größe"` → `"spätestens die Pulse"`, `"irgendwas Speciales"` → `"irgendwie Schlimmes"`) ve Türkçe'de (`"Brem şeyi"` → `"Brams şeyi"`, `"dinleyelim"` → `"zümleyelim"`) fonetik uydurmalara yol açtığı kanıtlanmıştır. Üstelik `Silero VAD v6.2.0` sayesinde tam 32 katmanlı `Large-v3` zaten **`~20x` gerçek zamanlı** (94 dakikalık kaydı ~4-5 dakikada bitirecek kadar hızlı) çalıştığından, doğruluktan ödün veren 4 katmanlı `Turbo` modeline gerek kalmamıştır.
5. **`Qwen3-ASR-0.6B` (1.88 GB, `8.4/10`):** `Large-v3 (Q5_0)` (`1.08 GB`, `9.5/10`) modelinden daha büyük olmasına rağmen daha düşük doğruluk (`8.4/10`) vermiş, `rec7_s3_cad_tech` klibinde `"Du klickst, klickst, klickst"` tekrarına düşmüş ve kısa Türkçe klipte harf kaymaları (`"sohren"`, `"ilpaşım"`) üretmiştir. `Qwen3-ASR-1.7B` (`9.6/10`, `0` döngü) varken `0.6B` tutmak mantıksızdır.
6. **`NVIDIA Parakeet TDT 0.6B v3 (MLX)` *(Test edildi, entegre edilmedi)*:** Almanca'da çok hızlı (`36.23x`) ve sessizlikte `0/5` yanlış pozitif verse de **Türkçe desteği sıfırdır** (`short_freunder` ve `rec3_s1` kliplerinde **0 kelime** üretti), `C++` terimini **`C<unk>`** olarak bozdu ve harici Python/MLX çalışma zamanı gerektirdi.

---

### 2. Uçtan Uca 5 Aşamalı Ses ve Transkripsiyon Hattı (Pipeline Architecture)

Her ses dosyası hem **`WhisperCppEngine`** hem de **`Qwen3ASREngine`** için aşağıdaki 5 aşamalı deterministik hattan geçer:

```text
[ Ses / Video Dosyası (.m4a, .mp3, .wav, .ogg, .opus, .mp4, .mkv ...) ]
                                  │
                                  ▼
   AŞAMA 1: AudioDecoder (16 kHz Mono Float32 PCM, AVAudioQuality.max + FFmpeg Fallback)
                                  │
                                  ▼
   AŞAMA 2: AudioConditioner (Saf Swift Accelerate / vDSP)
            ├─ 2.1 DC Offset Temizliği (vDSP_meanv + vDSP_vsadd)
            ├─ 2.2 95 Hz 2. Derece Butterworth Yüksek Geçiren Filtre (Q = 0.7071)
            └─ 2.3 Konuşma Modülasyonu Kapılı Doğrusal Kısık-Ses Kazancı
                   (Yalnızca 0.002 < p90 < 0.025 ve p90 > max(p15 * 1.8, 0.003) ise <= 4.0x + tanh 0.95)
                                  │
                                  ▼
   AŞAMA 3: Çift Katmanlı VAD & Zorunlu <= 28.0 sn Bağımsız Dilimleme
            ├─ 3.1 Hızlı Enerji Ön-Kapısı: AudioVAD.detectSpeech (maxFrameRMS < 0.012 ise anında boş dön)
            ├─ 3.2 Birincil Nöral VAD: SileroVAD v6.2.0 (whisper_vad_segments_from_samples,
            │      threshold=0.35, minSpeech=200ms, minSilence=500ms, maxSpeech=28s, pad=250ms, bridge=0.8s)
            └─ 3.3 Çevrimdışı Yedek & Zorunlu Üst Sınır: Qwen3ASREngine.splitSpeechSegments(maxDuration: 28.0s)
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
   AŞAMA 4A: WhisperCppEngine          AŞAMA 4B: Qwen3ASREngine
   (Large-v3 FP16 / Large-v3 Q5_0)     (Qwen3-ASR-1.7B Saf C CQwenASR)
   • use_gpu = true (Metal)            • Accelerate BLAS + NEON (-O3 -ffast-math)
   • flash_attn = true                 • segment_sec = 0.0, skip_silence = 0
   • BEAM_SEARCH (beam_size = 5)       • past_text_conditioning = 0 (noContext=true)
   • no_context = true (-mc 0)         • qwen_set_threads(threads)
   • suppress_nst = true (-sns)        • qwen_set_force_language("German"/"Turkish"/...)
   • no_speech_thold = 0.60            • qwen_set_prompt(initialPrompt)
   • entropy_thold = 2.40              • Segment.interpolateWords(...)
   • temperature = 0.0, inc = 0.20
                    └─────────────┬─────────────┘
                                  ▼
   AŞAMA 5: TranscriptPostProcessor & SRTFormatter
            ├─ Tier A: Saf Halüsinasyon & Dinamik Yayıncı Jenerik Temizliği (Almanca fiil/teknik kök korumalı)
            ├─ Tier B: Tek Başına Outro/Boilerplate Elemesi ("Vielen Dank", "Amen", "Thank you" ...)
            ├─ Tier C: Cümle İçi / Segmentler Arası N-Gram, Ping-Pong ve Tek-Kelime Döngü Tekilleştirmesi
            └─ SRTFormatter: <= 42 karakter/satır, <= 2 satır/blok SubRip (.srt) zaman damgası üretimi
```

---

### 3. Aşama ve Parametrelerin Deneysel Gerekçeleri ("Neden Bu Değer?")

#### Aşama 1 — `AudioDecoder.swift` (`Sources/TranskriptHubCore/Audio/AudioDecoder.swift`)
- **`targetSampleRate = 16000.0` (Mono `Float32`):** Hem Whisper'ın Log-Mel spektrogram çıkarıcısı hem de `CQwenASR` ve `SileroVAD v6.2.0` doğrudan `16 kHz` mono `Float32` bekliyor.
- **`converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue`:** `48 kHz` / `44.1 kHz` kaynaklardan `16 kHz`'e inerken yüksek frekanslı sessiz ünsüzlerin (`s, sch, f, t, k, ç, ş`) örtüşme (aliasing) kaybını önler.
- **`decodeViaFFmpeg(fileURL:)` Yedeği:** `AVAudioFile` tarafından yerel açılmayan `.ogg`, `.opus` (WhatsApp sesli notları), `.wma` ve `.webm` kapsayıcılarını otomatik olarak `16 kHz` mono PCM'e çevirir.

#### Aşama 2 — `AudioConditioner.swift` (`Sources/TranskriptHubCore/Audio/AudioConditioner.swift`)
- **Adım 2.1 — DC Offset Temizliği (`vDSP_meanv` + `vDSP_vsadd`):** Mikrofon ADC'lerinden gelen sabit DC kaymasını sıfırlar; böylece yüksek geçiren IIR filtrenin başlangıç sıçraması ve RMS eşik kayması engellenir.
- **Adım 2.2 — `highPassCutoffHz = 95.0` (2. Derece Butterworth HPF, `Q = 0.70710678`):**
  - *Neden `95 Hz`?* İnsan konuşmasının temel frekansı (F0) ve birinci formant enerjisi `>= 100 Hz` bölgesindedir; buna karşılık masa darbesi, mikrofon tutuş gürültüsü, klima/fan uğultusu ve araç motoru alt harmonikleri `10–90 Hz` bandında yoğunlaşır.
  - *Deneysel Kanıt:* `short_rec4_silence`, `short_rec5`, `short_rec6` ve `rec_main_s1` kliplerindeki `-38 dB` masa tıkırtıları Whisper'da `"*tap* *tap*"`, `"Hvað er það?"` ve `"Norske Skogsforskning"` halüsinasyonlarını tetikliyordu; `95 Hz` Butterworth filtresi konuşma formantlarına dokunmadan bu alt frekans darbelerini sildi.
- **Adım 2.3 — Konuşma Modülasyonu Kapılı Doğrusal Kısık-Ses Kazancı:**
  - *Koşul:* 20 ms çerçevelerin sıralı RMS dağılımında `0.002 < p90 < 0.025` (`-54 dBFS .. -32 dBFS`) **VE** `p90 > max(p15 * 1.8, 0.003)`.
  - *Kazanç:* `gain = min(4.0, 0.050 / p90)` (maksimum `+12 dB`), `|scaled| > 0.85` üzerinde `tanh(scaled) * 0.95` yumuşak tepe sınırlayıcı.
  - **⚠️ KRİTİK AJAN UYARISI — Neden Koşulsuz `FFmpeg loudnorm` / `dynaudnorm` / `RNNoise` Kullanılmadı?**
    1. Kontrollü A/B deneyimizde (`task-2598`), internette sıkça önerilen `highpass=f=100,loudnorm=I=-16:TP=-1.5:LRA=11` filtresi zaten yüksek sesli olan dış ortam Türkçe kaydına (`rec3_s1`, ortalama `-25.3 dB`, `%6.1 <-45 dB`) uygulandığında dinamik aralığı ezdi, arka plan motor gürültüsünü pompaladı ve `Whisper Large-v3`'ün yakaladığı kelime sayısını **`117` kelimeden `65` kelimeye düşürdü** (üstelik `"İzlediğiniz için teşekkür ederim."` halüsinasyonu üretti).
    2. Buna karşılık yalnızca gerçekten kısık (`p90 < 0.025`) ve konuşma modülasyonu taşıyan (`p90 > p15 * 1.8`) kayıtlara doğrusal kazanç uygulayan `AudioConditioner`:
       - Yüksek sesli `rec3_s1` (`p90 = 0.0839` → `gain = 1.00x`) ve `short_freunder` (`p90 = 0.0381` → `gain = 1.00x`) kliplerinin dinamiklerine hiç dokunmadı (`short_freunder` `19 → 26` kelimeye çıktı, baştaki kısık `"iyiydim."` kelimesi kurtarıldı; `rec3_s1` `113` kelimeyle korundu).
       - Sabit fan uğultusu içeren `rec_main_s1` (`p90 / p15 < 1.8`) üzerinde gürültüyü yükseltmedi.
       - Çok kısık ofis/mühendislik kaydı `rec7_s3_cad_tech` (`-43.2 dB`, `p90 = 0.0105` → `gain = 4.00x`) ve `rec2_s1` (`p90 = 0.0102` → `gain = 4.00x`) kliplerini `+12 dB` temiz yükselterek `Large-v3` kelime yakalamasını `123 → 152` kelimeye, `Qwen3-ASR-1.7B` kelime yakalamasını `163 → 184` kelimeye çıkardı (ve Qwen'in `"Notsche"` hatasını `"Notch"` olarak düzeltti).

#### Aşama 3 — Çift Katmanlı VAD (`SileroVAD.swift` + `AudioVAD.swift`) ve `<= 28.0 sn` Bağımsız Dilimleme
- **Birincil Nöral Dedektör (`SileroVAD.swift` — `ggml-silero-v6.2.0.bin`, `864 KB`):**
  - Gömülü `whisper.xcframework` (`v1.9.2`) içindeki `whisper_vad_init_from_file_with_params` + `whisper_vad_segments_from_samples` C API'sini CPU BLAS üzerinde (`cparams.use_gpu = false`, `n_threads = 4`, `~170x–260x` gerçek zamanlı) çalıştırır.
  - **Parametreler ve Nedenleri:**
    - `threshold = 0.35`: Varsayılan `0.50` eşiği `short_freunder.wav` başındaki yumuşak `"iyiydim"` (`0.00–1.21 sn`) kelimesini kesiyordu (`1.60 sn`'den başlatıyordu). `0.35` eşiği `AudioConditioner` ile birlikte `0.00–1.21 sn` aralığını eksiksiz yakaladı **VE** 5 sessizlik tuzağının tamamında (`sil5`) yanlış pozitif oranını **`5/5 (32–50 kelime) → 0/5 (0 kelime)`** seviyesine indirdi.
    - `minSpeechDurationMs = 200`: `< 200 ms` anlık tıkırtıları eler.
    - `minSilenceDurationMs = 500`: Doğal nefes duraklamalarında cümleyi erken bölmez.
    - `maxSpeechDurationSeconds = 28.0`: Hem Whisper'ın `30.0 sn` konumsal gömme (positional embedding) penceresinin hem de `Qwen3-ASR`'ın kararlılık penceresinin güvenli altında kalır.
    - `speechPadMs = 250` ve `bridgeGapSeconds = 0.80` (birleşik süre `<= 28.0 sn` kaldığı sürece).
  - **⚠️ KRİTİK AJAN UYARISI 1 — `whisper_vad_segments_get_segment_t0/t1` Birimi:** `whisper.cpp 1.9.2` içinde bu fonksiyonlar saniye değil **santimetre-saniye (`centiseconds`, `100.0 == 1.0 sn`)** döndürür (`Double(t0) / 100.0`). Bunu `1.0` veya `1000.0`'e bölmek tüm zaman damgalarını bozar.
  - **⚠️ KRİTİK AJAN UYARISI 2 — Neden `wparams.vad = true` Dahili Birleştiriciyi KULLANMIYORUZ?**
    - `whisper.cpp` içinde `wparams.vad = true` açıldığında, C çekirdeği tüm VAD segmentlerini tek bir yapay ses tamponunda uç uca yapıştırıp (`stitching`) tek bir `whisper_full()` çağrısı yapar.
    - Deneyimizde (`task-2598` / `rec3_s1`), `Large-v3` (`beam=5`) bu yapıştırılmış sınırda (`00:00:39.100 --> 00:01:09.310`, `30.21 sn` atlama) `no_speech` tetikleyip kalan konuşma pencerelerini düşürdü (`117` kelimeden `28–44` kelimeye çöküş).
    - Bunun yerine `SileroVAD.detectSpeech` ile gerçek `(start, end)` `SpeechSegment` aralıklarını alıp `WhisperCppEngine` ve `Qwen3ASREngine` içinde **her gerçek ses dilimini bağımsız olarak** kendi gerçek `offsetSeconds` zaman ofsetiyle işliyoruz. Bu sayede sınır çökmesi ve zaman damgası kayması imkânsızdır.
- **Hızlı Enerji Ön-Kapısı ve Çevrimdışı Yedek (`AudioVAD.swift`):**
  - 20 ms `vDSP_rmsqv` çerçeveleri üzerinde `minSpeechRMS = 0.012` ve konuşma-altı (`< 0.012`) gürültü tabanı tahmini (`maxAdaptiveThresholdRMS = 0.014`) yapar. Tamamen sessiz kayıtları nöral VAD belleği ayırmadan anında (`< 1 ms`) reddeder ve `ggml-silero-v6.2.0.bin` dosyası yoksa tam yedek olarak çalışır.

#### Aşama 4A — `WhisperCppEngine.swift` (`Large-v3` & `Large-v3 (Q5_0)`) Parametreleri
- **`cparams.use_gpu = true` & `cparams.flash_attn = true`:** Apple Silicon Metal GPU üzerinde Flash Attention'ı etkinleştirir; WER matematiksel olarak aynı kalırken uzun sekanslarda bellek bant genişliği darboğazını kaldırır. (Sabit 30 sn sıfır-dolgu zorunluluğu olan CoreML `.mlmodelc` yerine değişken uzunluklu `1..28 sn` VAD dilimlerinde saf Metal + `flash_attn` çok daha hızlıdır.)
- **`strategy = WHISPER_SAMPLING_BEAM_SEARCH` (`beamSize = 5`):**
  - *Deneysel Kanıt:* Greedy (`beamSize = 1`) kod çözme `short_freunder.wav` başındaki yumuşak `"iyiydim"` kelimesini atlarken ve `"ilk başım"` kelimesini `"ilk başın"` yaparken, `beamSize = 5` (`task-2598` ve `task-2784`) doğru kelimeleri ve `rec7_s4_python_pause` içindeki **7/8** Python terimini kurtardı. `SileroVAD` sessizlikleri kestiği için `beamSize = 5` açıkken bile `Large-v3` **`~20x` gerçek zamanlı** hızda çalışır.
- **`wparams.no_context = options.noContext` (Varsayılan: `true`, CLI: `-mc 0`):**
  - *Deneysel Kanıt:* `no_context = false` bırakıldığında 32 katmanlı `Large-v3` bir önceki 28 sn'lik pencerenin çıktısını bir sonraki pencereye ön-koşul yaptığı için duraklamalarda **13 tekrar döngüsüne** girdi ve `rec7_s3_cad_tech` klibinde CAD terimlerinin yarısından fazlasını kaçırdı (**3/7**). `no_context = true` yapıldığında döngüler sıfırlandı ve CAD terim başarısı **3/7 → 7/7**'ye çıktı.
  - *(Not: `AppViewModel.swift` satır 2325 ve 2519'da daha önce sabit `noContext: false` unutulduğu tespit edilip kullanıcının `antiHallucinationEnabled` ayarına bağlanmıştır.)*
- **`wparams.suppress_nst = true` (`-sns`) & `wparams.suppress_blank = true`:** Konuşma dışı simgeleri (`♪`, `* musik *`, `[Applaus]`) halüsinasyon sıçrama tahtası olmadan bastırır.
- **`wparams.no_speech_thold = 0.60`, `wparams.entropy_thold = 2.40`, `wparams.temperature = 0.0`, `wparams.temperature_inc = 0.20`:** Deterministik `0.0` sıcaklıkla başlar; Shannon entropisi `2.40` eşiğinin altına düşerse (tekrar döngüsü belirtisi) sıcaklığı `0.20` artırarak döngüyü kırar.
- **`wparams.carry_initial_prompt = (normalizedPrompt != nil)`:** Kullanıcı `--prompt` verdiğinde (`"SPSM, DXF, Geo, Mesh, PyWrapper..."`), `no_context = true` olsa bile her 28 sn'lik dilime yalnızca bu temiz terim sözlüğünü taşır (önceki dilimin hatalı çıktısını değil!).

#### Aşama 4B — `Qwen3ASREngine.swift` (`Qwen3-ASR-1.7B` Saf C `CQwenASR`) Parametreleri
- **Derleme Bayrakları (`Package.swift` — `Sources/CQwenASR`):**
  - `-DUSE_BLAS -DACCELERATE_NEW_LAPACK -O3 -ffast-math` + `-framework Accelerate`.
  - *Deneysel Kanıt:* `-O3 -ffast-math` bayrakları olmadan SwiftPM Debug derlemesinde `short_freunder.wav` (`10.23 sn`) `41.00 sn` sürerken, bu bayraklarla **`4.19 sn`** (**10 kat hızlanma**) sürmüştür.
- **Zorunlu `<= 28.0 sn` VAD Parçalama (`Qwen3ASREngine.maxChunkSeconds = 28.0`):**
  - **⚠️ KRİTİK AJAN UYARISI:** Deneyimizde `Qwen3-ASR-1.7B` (`mlx-audio` 8-bit) VAD ve `<= 28 sn` parçalama olmadan seyrek konuşmalı `150 sn`'lik `rec2_s1` klibine doğrudan verildiğinde **2.731 kelimelik `"Hallo. Hallo. ..."` sonsuz döngüsüne** girip `184.27 sn` (`0.81x` RTF) harcamıştır. Aynı klip `<= 28 sn` VAD dilimleriyle saf C `Qwen3ASREngine`'e verildiğinde **`5.49 sn` (`27.35x` RTF) içinde `22` kelime ve `0` döngüyle** tamamlanmıştır. Bu nedenle `Qwen3ASREngine` içinde `ctx.pointee.segment_sec = 0.0` ve `ctx.pointee.skip_silence = 0` yapılarak tüm bölümleme Swift tarafındaki `AudioConditioner + SileroVAD + splitSpeechSegments(maxDuration: 28.0)` katmanına devredilmiştir.
- **`ctx.pointee.past_text_conditioning = options.noContext ? 0 : 1`:** Dilimler arası hata bulaşmasını önlemek için varsayılan olarak `0` (`noContext = true`) tutulur.
- **`Qwen3ASREngine.mapLanguageCode(_:)`:** ISO-639-1 kodlarını (`"de"`, `"tr"`, `"en"`, ...) Qwen3-ASR'ın beklediği kanonik İngilizce dil adlarına (`"German"`, `"Turkish"`, `"English"`, ...) çevirir; `"auto"` veya `nil` durumunda `qwen_set_force_language(ctx, nil)` ile Qwen'in kendi dil tespitini kullanır.

#### Aşama 5 — `TranscriptPostProcessor.swift` & `SRTFormatter.swift`
- **3 Katmanlı Cerrahi Temizlik (`TranscriptPostProcessor.swift`):**
  1. **Tier A (`pureHallucinationPhrases` & Dinamik Jenerik/Telif Regex'leri):** `"es heilt die göttliche kraft"`, `"amara.org"`, `"altyazı m k"` ve masaüstü testlerimizde yakalanan İskandinav sessizlik halüsinasyonlarını (`"teksting av nicolai winther"`, `"hvað er það"`, `"það er það er það"`, `"norske skogsforskning"`) hem segment hem cümle seviyesinde siler. Dinamik yayıncı (`ZDF`, `ARD`, `ORF`, `Subtitles by...`) filtreleri, gerçek Almanca teknik cümleleri (`creditSentenceVerbRegex`, `creditTechStemRegex`) yanlışlıkla silmemek için fiil ve mühendislik kök korumasına sahiptir.
  2. **Tier B (`standaloneBoilerplatePhrases`):** `"vielen dank"`, `"amen"`, `"thank you for watching"`, `"izlediğiniz için teşekkürler"` gibi ifadeleri **yalnızca tek başına bağımsız bir segment olarak** ortaya çıktığında siler; gerçek konuşma cümlesinin parçasıysa asla dokunmaz.
  3. **Tier C (Döngü ve Tek-Kelime Tekilleştirme):** Cümle içi ardışık n-gram tekrarlarını (`3+` tekrar → `1`), segmentler arası A-B-A-B ping-pong döngülerini ve tek kelimelik çökme kuyruklarını (`"Ich habe, das ist, das ist, das ist..."`) temizler.
- **`SRTFormatter.swift`:** Kelime zaman damgalarını kullanarak her altyazı bloğunu `<= 42` karakter/satır ve `<= 2` satır/blok standardına göre kelime ortasından bölmeden üretir (`>= 100` saat zaman damgalarını taşmadan destekler).

---

### 4. Gelecek Yapay Zeka Ajanları İçin Kırmızı Çizgiler (Invariants Not To Break)

1. **`WhisperModelCatalog.availableModels` içine `< 1 GB` veya doğruluğu `< 9.5/10` olan model eklemeyin** (ve sıralamayı her zaman `sizeBytes` artan sırada, `summary` uzunluğunu `<= 40` karakter tutun — `FolderWatcherTests` bunu zorunlu kılar).
2. **`AudioConditioner` içinde koşulsuz `loudnorm` veya `p50` tabanlı eşik kullanmayın:** Konuşmacının `%50`'den fazla konuştuğu kayıtlarda `p50` konuşmanın içine düşer; gürültü tabanı referansı mutlaka **`p15`** (`p90 > max(p15 * 1.8, 0.003)`) olmalıdır.
3. **`WhisperCppEngine` içinde `wparams.vad = true` açmayın:** Ses kesitlerini her zaman Swift tarafında `SileroVAD.detectSpeech` (+ `AudioVAD.detectSpeech` yedeği) ile çıkarıp `<= 28.0 sn` bağımsız dilimler halinde `whisper_full()` fonksiyonuna gönderin.
4. **`SileroVAD.swift` içinde `whisper_vad_segments_get_segment_t0/t1` dönüş değerini her zaman `100.0`'e bölün** (`centiseconds -> seconds`).
5. **`Qwen3ASREngine` içinde `maxChunkSeconds <= 28.0` üst sınırını asla kaldırmayın** ve `Package.swift` içindeki `CQwenASR` `-O3 -ffast-math` bayraklarını silmeyin.
6. **`AppViewModel.swift` içinde `noContext` parametresini asla sabit `false` yapmayın** (`noContext: antiHallucination` olarak kalmalıdır) ve tamamlanan kuyruk öğelerinde `"Ses Transkript Ediliyor..."` alt başlık temizleme korumasını (`updateItem` + görünüm katmanı) kaldırmayın.
7. **Her değişiklikten sonra `swift test` (`303/303` test) ve `gitleaks git .` (`0` sızıntı) çalıştırılmadan işlem tamamlanmış sayılmaz.**

---

## 🏗️ Proje Yapısı (Architecture)

```text
TranskriptHub
├── Sources/
│   ├── CQwenASR/                  # Saf C Qwen3-ASR çekirdeği (Apple Accelerate BLAS + NEON, -O3 -ffast-math)
│   ├── TranskriptHubCore/         # Saf Swift Çekirdek Kütüphanesi
│   │   ├── Audio/                 # AudioDecoder, AudioConditioner (vDSP), SileroVAD v6.2.0, AudioVAD, AudioValidator
│   │   ├── Transcription/         # WhisperCppEngine, Qwen3ASREngine, TranscriptionEngineFactory, TranscriptPostProcessor, WhisperModelCatalog
│   │   ├── Output/                # OutputWriter (atomik .txt), SRTFormatter (<=42 krk SubRip .srt)
│   │   ├── Cache/                 # TranscriptCacheManager (isim + süre + externalID akıllı önbellek)
│   │   ├── Database/              # GRDB.swift SQLite kalıcı durum makinesi
│   │   └── System/                # ClipboardMonitor, FolderWatcher (iCloud & Voice Memos)
│   ├── TranskriptHubApp/          # SwiftUI 6 macOS Arayüzü (UnifiedStudioHubView, MenuBarMiniWindow)
│   └── transkripthub-cli/         # Komut satırı arayüzü (--model, --lang, --no-context, --prompt, --srt)
├── Frameworks/
│   └── whisper.xcframework/       # Metal GPU + Flash Attention + Silero VAD C API destekli whisper.cpp (v1.9.2)
└── Tests/
    └── TranskriptHubCoreTests/    # 303 birim, stres ve 4-katmanlı E2E doğrulama testi
```

---

## ⌨️ Klavye Kısayolları (Keyboard Shortcuts)

| Kısayol | İşlem |
|---|---|
| <kbd>⌘</kbd> + <kbd>Return</kbd> | Kuyruk Transkripsiyonunu Başlat |
| <kbd>⌘</kbd> + <kbd>V</kbd> | Panodan Bağlantı Yapıştır |
| <kbd>⌘</kbd> + <kbd>O</kbd> | Ses / Video Dosyası Seç |
| <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>T</kbd> | Transkript Klasörünü Finder'da Aç |
| <kbd>⌘</kbd> + <kbd>K</kbd> | Komut Paletini Aç |
| <kbd>⌘</kbd> + <kbd>,</kbd> | Ayarları Aç |
| <kbd>⌘</kbd> + <kbd>1</kbd> / <kbd>2</kbd> / <kbd>3</kbd> | Kuyruk / Geçmiş / İzlenen Klasörler Görünümü |
| <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>B</kbd> | Pano İzlemeyi Aç / Kapat |

---

## 🚀 Kurulum ve Derleme (Getting Started & Building from Source)

### 🇹🇷 Tek Tıkla Kurulum
1. Yukarıdaki **Download Transkript Hub** butonuna tıklayarak (veya [GitHub Releases](../../releases) sayfasından) en güncel **`TranskriptHub.dmg`** dosyasını indirin.
2. İndirilen DMG dosyasını açın ve **Transkript Hub** uygulamasını **Applications (Uygulamalar)** klasörünüze sürükleyin.
3. Uygulamayı açın; model yöneticisinden **`Large-v3` (3.09 GB)**, **`Qwen3-ASR-1.7B` (4.70 GB)** veya **`Large-v3 (Q5_0)` (1.08 GB)** modelini seçip ses/video dosyalarınızı sürükleyin.

### 🛠️ Kaynak Koddan Derleme ve CLI Kullanımı

```bash
# 1. Tüm birim ve E2E testlerini çalıştır (303 test)
swift test

# 2. Release ikililerini ve imzalı DMG / .app paketini üret
./scripts/package_dmg.sh

# 3. CLI üzerinden Large-v3 + Silero VAD + AudioConditioner + SRT ile transkripsiyon
.build/release/transkripthub-cli transcribe "kayit.m4a" \
  --model large-v3 \
  --lang de \
  --no-context \
  --srt \
  --prompt "SPSM, DXF, Geo, Mesh, PyWrapper, Paraview, Assembly, MachineDataLibrary"

# 4. CLI üzerinden Qwen3-ASR-1.7B (Saf C Accelerate) ile transkripsiyon
.build/release/transkripthub-cli transcribe "kayit.m4a" \
  --model qwen3-asr-1.7b \
  --lang de \
  --no-context \
  --srt
```

---

## 📄 Lisans (License)

Bu proje [MIT Lisansı](LICENSE) altında lisanslanmıştır. Üçüncü taraf bileşenler (`whisper.cpp`, `antirez/qwen-asr`, `Silero VAD`, `GRDB.swift`, `yt-dlp`, `Deno`) kendi açık kaynak lisanslarına tabidir.
