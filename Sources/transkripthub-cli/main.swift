import Foundation
import TranskriptHubCore
import whisper

@main
struct TranskriptHubCLI {
    static func main() async {
        let args = CommandLine.arguments
        
        guard args.count >= 2 else {
            printUsage()
            return
        }
        
        let command = args[1]
        switch command {
        case "transcribe":
            await handleTranscribe(arguments: Array(args.dropFirst(2)))
        case "youtube":
            await handleYouTube(arguments: Array(args.dropFirst(2)))
        case "batch":
            await handleBatch(arguments: Array(args.dropFirst(2)))
        case "tools":
            await handleTools(arguments: Array(args.dropFirst(2)))
        case "models":
            await handleModels(arguments: Array(args.dropFirst(2)))
        case "version", "--version", "-v":
            print("Transkript Hub v1.0 (Apple Silicon Native)")
            print("whisper.cpp engine: \(String(cString: whisper_version()))")
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Bilinmeyen komut: \(command)")
            printUsage()
        }
    }
    
    static func printUsage() {
        print("""
        Transkript Hub CLI v1.0 — Apple Silicon Yerel Transkripsiyon
        
        Kullanım:
          transkripthub-cli batch <url1> <url2> ... [seçenekler]
          transkripthub-cli youtube <youtube_url> [seçenekler]
          transkripthub-cli transcribe <ses_dosyasi> [seçenekler]
          transkripthub-cli tools [install | status]
          transkripthub-cli models [download <model_adi> | list]
          transkripthub-cli version
        
        Batch Seçenekleri:
          --file <dosya>    İçinde YouTube linkleri olan bir metin dosyası
          --model <ad>      Model (tiny, base, small, medium, large-v3-turbo, large-v3-turbo-q5_0) [Varsayılan: tiny]
          --lang <kod>      Dil kodu (tr, de, en veya auto) [Varsayılan: auto]
        """)
    }
    
    static func handleBatch(arguments: [String]) async {
        var rawURLs: [String] = []
        var modelName = "tiny"
        var language: String? = nil
        
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--file", i + 1 < arguments.count {
                let filePath = arguments[i + 1]
                if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    let parsed = URLParser.parseBulk(content)
                    rawURLs.append(contentsOf: parsed.map(\.canonicalURL))
                } else {
                    print("Hata: Belirtilen dosya okunamadı: \(filePath)")
                }
                i += 2
            } else if arg == "--model", i + 1 < arguments.count {
                modelName = arguments[i + 1]
                i += 2
            } else if arg == "--lang", i + 1 < arguments.count {
                language = arguments[i + 1]
                i += 2
            } else if !arg.hasPrefix("-") {
                if let parsed = URLParser.parseSingle(arg) {
                    rawURLs.append(parsed.canonicalURL)
                } else {
                    print("Uyarı: Geçersiz URL atlandı: \(arg)")
                }
                i += 1
            } else {
                i += 1
            }
        }
        
        guard !rawURLs.isEmpty else {
            print("Hata: İşlenecek geçerli bir video linki bulunamadı.")
            printUsage()
            return
        }
        
        guard let selectedModel = WhisperModel(rawValue: modelName) else {
            print("Geçersiz model: \(modelName).")
            return
        }
        
        print("=== Transkript Hub — Toplu Batch İşlemi Başlatılıyor ===")
        print("Toplam Video Sayısı: \(rawURLs.count)")
        print("Model: \(selectedModel.rawValue)")
        print("Dil: \(language ?? "Otomatik")")
        
        do {
            let database = try AppDatabase.makeShared()
            let jobManager = JobManager(database: database)
            
            // 1. Recover state
            try await jobManager.recoverState()
            
            // 2. Create batch
            let batch = try await jobManager.createYouTubeBatch(urls: rawURLs, language: language)
            print("Batch oluşturuldu (ID: \(batch.id))")
            
            // 3. Process with live updates
            let totalCount = rawURLs.count
            let result = try await jobManager.processBatch(batchID: batch.id, model: selectedModel) { job in
                let titleStr = job.title ?? job.externalID ?? "Bilinmiyor"
                print(" -> [Video \(job.sequence)/\(totalCount)] \(titleStr): \(job.state.uppercased())")
            }
            
            switch result {
            case .assembled(let outputURL, let isPartial):
                print("\n=======================================================")
                if isPartial {
                    print("⚠️ Kısmi Başarı: Bazı videolar indirilemedi ancak başarılı tüm videolar birleştirildi!")
                } else {
                    print("🎉 Başarılı: Tüm videolar eksiksiz birleştirildi!")
                }
                print("Birleşik Çıktı Dosyası: \(outputURL.path)")
                print("Geçici ses dosyaları temizlendi.")
                print("=======================================================")
            case .waiting(let count):
                print("İşlem henüz bitmedi, bekleyen video sayısı: \(count)")
            case .empty:
                print("Hata: Birleştirilecek hiçbir video kaydı bulunamadı.")
            }
            
        } catch {
            print("\nBatch çalıştırma hatası: \(error.localizedDescription)")
        }
    }
    
    static func handleTools(arguments: [String]) async {
        let toolManager = ToolManager()
        let sub = arguments.first ?? "status"
        
        if sub == "status" {
            print("Yönetilen Araç Durumları:")
            print(" - yt-dlp: \(toolManager.isYTDLPReady() ? "✅ Hazır (\(toolManager.ytdlpExecutableURL.path))" : "⏳ Kurulu değil")")
            print(" - deno:   \(toolManager.isDenoReady() ? "✅ Hazır (\(toolManager.denoExecutableURL.path))" : "⏳ Kurulu değil")")
            return
        }
        
        if sub == "install" {
            do {
                print("Gerekli bağımsız araçlar indiriliyor ve yapılandırılıyor...")
                try await toolManager.ensureToolsReady { message, ratio in
                    let percent = Int(ratio * 100)
                    print("\r[\(message)] %\(percent)", terminator: "")
                    fflush(stdout)
                }
                print("\n✅ Tüm araçlar hazır!")
            } catch {
                print("\n❌ Araç kurulum hatası: \(error.localizedDescription)")
            }
        }
    }
    
    static func handleYouTube(arguments: [String]) async {
        guard let urlStr = arguments.first, !urlStr.hasPrefix("-") else {
            print("Hata: YouTube video linki belirtilmedi.")
            printUsage()
            return
        }
        
        guard let parsed = URLParser.parseSingle(urlStr) else {
            print("Hata: Geçersiz YouTube linki: \(urlStr)")
            return
        }
        
        var modelName = "tiny"
        var language: String? = nil
        var customOutput: String? = nil
        var insertTimestamps = false
        
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--model", i + 1 < arguments.count {
                modelName = arguments[i + 1]
                i += 2
            } else if arg == "--lang", i + 1 < arguments.count {
                language = arguments[i + 1]
                i += 2
            } else if arg == "--output", i + 1 < arguments.count {
                customOutput = arguments[i + 1]
                i += 2
            } else if arg == "--timestamps" {
                insertTimestamps = true
                i += 1
            } else {
                i += 1
            }
        }
        
        guard let selectedModel = WhisperModel(rawValue: modelName) else {
            print("Geçersiz model: \(modelName).")
            return
        }
        
        print("=== Transkript Hub — YouTube İşlemi Başlatılıyor ===")
        print("Video URL: \(parsed.canonicalURL) [ID: \(parsed.videoID)]")
        print("Model: \(selectedModel.rawValue)")
        
        // 1. Prepare Tools
        let toolManager = ToolManager()
        do {
            if !toolManager.isYTDLPReady() || !toolManager.isDenoReady() {
                print("\n[1/4] Gerekli bağımsız YouTube araçları indiriliyor...")
                try await toolManager.ensureToolsReady { msg, ratio in
                    let percent = Int(ratio * 100)
                    print("\r\(msg): %\(percent)", terminator: "")
                    fflush(stdout)
                }
                print("")
            } else {
                print("\n[1/4] YouTube araçları hazır.")
            }
        } catch {
            print("\nAraç hazırlama hatası: \(error.localizedDescription)")
            return
        }
        
        // 2. Fetch Video Audio
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("TranskriptHub_Job_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        
        print("\n[2/4] Ses ve metadata indiriliyor...")
        let fetchedMedia: FetchedMedia
        let ytdlp = YTDLPClient(toolManager: toolManager)
        do {
            fetchedMedia = try await ytdlp.fetch(url: parsed.canonicalURL, into: workspace) { ratio in
                let percent = Int(ratio * 100)
                print("\rİndirme İlerlemesi: %\(percent)", terminator: "")
                fflush(stdout)
            }
            print("\nVideo: \(fetchedMedia.metadata.title)")
            if let ch = fetchedMedia.metadata.channel {
                print("Kanal: \(ch)")
            }
        } catch {
            print("\nYouTube indirme hatası: \(error.localizedDescription)")
            return
        }
        
        // 3. Decode Audio
        print("\n[3/4] Ses çözülüyor (AVFoundation)...")
        let decoder = AudioDecoder()
        let preparedAudio: PreparedAudio
        do {
            preparedAudio = try decoder.decode(fileURL: fetchedMedia.localAudioURL)
            let durStr = String(format: "%.1f", preparedAudio.duration)
            print("Ses çözüldü (Süre: \(durStr) sn)")
        } catch {
            print("Ses çözme hatası: \(error.localizedDescription)")
            return
        }
        
        // 4. Transcribe with Metal
        print("\n[4/4] Metal GPU ile transkript ediliyor...")
        let modelManager = ModelManager()
        let modelURL: URL
        do {
            if !modelManager.isModelDownloaded(selectedModel) {
                modelURL = try await modelManager.downloadModel(selectedModel)
            } else {
                modelURL = modelManager.localURL(for: selectedModel)
            }
            
            let engine = try WhisperCppEngine(modelPath: modelURL.path)
            let options = TranscriptionOptions(language: language)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try await engine.transcribe(preparedAudio, options: options) { ratio in
                let percent = Int(ratio * 100)
                print("\rTranskripsiyon İlerlemesi: %\(percent)", terminator: "")
                fflush(stdout)
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print(String(format: "\nTranskripsiyon tamamlandı (%.2f sn)", elapsed))
            
            // Post-processing
            let postProcessor = TranscriptPostProcessor()
            let formattedText = postProcessor.process(
                segments: result.segments,
                options: PostProcessorOptions(insertTimestamps: insertTimestamps)
            )
            
            // Save Output using OutputWriter (Başlık.txt)
            let outputWriter = OutputWriter()
            let targetURL: URL
            if let custom = customOutput {
                targetURL = URL(fileURLWithPath: custom)
            } else {
                targetURL = outputWriter.resolveUniqueURL(
                    forBaseName: fetchedMedia.metadata.title,
                    in: outputWriter.defaultOutputDirectory
                )
            }
            
            try outputWriter.write(content: formattedText, to: targetURL)
            print("\n🎉 Başarıyla tamamlandı!")
            print("Çıktı Dosyası: \(targetURL.path)")
            
        } catch {
            print("\nİşlem hatası: \(error.localizedDescription)")
        }
    }
    
    static func handleModels(arguments: [String]) async {
        let manager = ModelManager()
        if arguments.first == "list" || arguments.isEmpty {
            print("Desteklenen modeller ve durumları:")
            for m in WhisperModel.allCases {
                let downloaded = manager.isModelDownloaded(m)
                let status = downloaded ? "✅ İndirilmiş" : "⏳ Henüz indirilmedi"
                print(" - \(m.rawValue) (\(m.filename)) -> \(status)")
            }
            print("\nModeller klasörü: \(manager.modelsDirectory.path)")
            return
        }
        
        if arguments.first == "download", arguments.count >= 2 {
            let modelName = arguments[1]
            guard let model = WhisperModel(rawValue: modelName) else {
                print("Geçersiz model adı: \(modelName).")
                return
            }
            do {
                print("\(model.rawValue) modeli indiriliyor...")
                let path = try await manager.downloadModel(model) { progress in
                    let percent = Int(progress * 100)
                    print("\rİlerleme: %\(percent)", terminator: "")
                    fflush(stdout)
                }
                print("\nModel hazır: \(path.path)")
            } catch {
                print("\nİndirme hatası: \(error.localizedDescription)")
            }
        }
    }
    
    static func handleTranscribe(arguments: [String]) async {
        guard let firstArg = arguments.first, !firstArg.hasPrefix("-") else {
            print("Hata: Transkript edilecek ses dosyası belirtilmedi.")
            printUsage()
            return
        }
        
        let fileURL = URL(fileURLWithPath: firstArg)
        var modelName = "tiny"
        var language: String? = nil
        var outputPath: String? = nil
        var insertTimestamps = false
        
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--model", i + 1 < arguments.count {
                modelName = arguments[i + 1]
                i += 2
            } else if arg == "--lang", i + 1 < arguments.count {
                language = arguments[i + 1]
                i += 2
            } else if arg == "--output", i + 1 < arguments.count {
                outputPath = arguments[i + 1]
                i += 2
            } else if arg == "--timestamps" {
                insertTimestamps = true
                i += 1
            } else {
                i += 1
            }
        }
        
        guard let selectedModel = WhisperModel(rawValue: modelName) else {
            print("Geçersiz model: \(modelName).")
            return
        }
        
        print("=== Transkript Hub — Yerel İşlem Başlatılıyor ===")
        print("Girdi Dosyası: \(fileURL.path)")
        print("Model: \(selectedModel.rawValue)")
        
        // 1. Audio Decoding
        print("\n[1/3] Ses çözülüyor (AVFoundation 16 kHz Mono PCM)...")
        let decoder = AudioDecoder()
        let preparedAudio: PreparedAudio
        do {
            preparedAudio = try decoder.decode(fileURL: fileURL)
            let durationStr = String(format: "%.2f", preparedAudio.duration)
            print("Ses başarıyla çözüldü. Süre: \(durationStr) sn, Örnek Sayısı: \(preparedAudio.samples.count)")
        } catch {
            print("Ses çözme hatası: \(error.localizedDescription)")
            return
        }
        
        // 2. Model Preparation
        let modelManager = ModelManager()
        let modelURL: URL
        do {
            if !modelManager.isModelDownloaded(selectedModel) {
                print("\n[2/3] Model indiriliyor (\(selectedModel.filename))...")
                modelURL = try await modelManager.downloadModel(selectedModel)
            } else {
                modelURL = modelManager.localURL(for: selectedModel)
                print("\n[2/3] Model mevcut: \(modelURL.lastPathComponent)")
            }
        } catch {
            print("Model hazırlama hatası: \(error.localizedDescription)")
            return
        }
        
        // 3. Transcription
        print("\n[3/3] Metal GPU hızlandırmasıyla transkript ediliyor...")
        do {
            let engine = try WhisperCppEngine(modelPath: modelURL.path)
            let options = TranscriptionOptions(language: language)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try await engine.transcribe(preparedAudio, options: options) { progress in
                let percent = Int(progress * 100)
                print("\rTranskripsiyon İlerlemesi: %\(percent)", terminator: "")
                fflush(stdout)
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print(String(format: "\nİşlem tamamlandı: %.2f saniyede işlendi.", elapsed))
            
            // Post-processing
            let postProcessor = TranscriptPostProcessor()
            let postOptions = PostProcessorOptions(insertTimestamps: insertTimestamps)
            let formattedText = postProcessor.process(segments: result.segments, options: postOptions)
            
            print("\n----------------- TRANSKRİPT ÇIKTISI -----------------")
            print(formattedText)
            print("------------------------------------------------------")
            
            // Save Output using OutputWriter
            let outputWriter = OutputWriter()
            let targetURL: URL
            if let customOut = outputPath {
                targetURL = URL(fileURLWithPath: customOut)
            } else {
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                targetURL = outputWriter.resolveUniqueURL(
                    forBaseName: baseName,
                    in: fileURL.deletingLastPathComponent()
                )
            }
            
            try outputWriter.write(content: formattedText, to: targetURL)
            print("Çıktı başarıyla kaydedildi: \(targetURL.path)")
            
        } catch {
            print("\nTranskripsiyon hatası: \(error.localizedDescription)")
        }
    }
}
