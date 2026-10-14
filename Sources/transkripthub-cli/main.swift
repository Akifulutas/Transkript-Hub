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
          transkripthub-cli transcribe <ses_dosyasi> [seçenekler]
          transkripthub-cli models [download <model_adi> | list]
          transkripthub-cli version
        
        Seçenekler:
          --model <ad>      Model adı (tiny, base, small, medium, large-v3-turbo, large-v3-turbo-q5_0) [Varsayılan: base]
          --lang <kod>      Dil kodu (tr, de, en, veya auto) [Varsayılan: auto]
          --output <yol>    Çıktı TXT dosyası yolu [Varsayılan: <ses_dosyasi_adi>.txt]
          --timestamps      Paragraf başlarına [HH:MM:SS] zaman damgası ekler
        """)
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
                print("Geçersiz model adı: \(modelName). Seçenekler: \(WhisperModel.allCases.map(\.rawValue).joined(separator: ", "))")
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
        var modelName = "base" // Fast & small for initial verification
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
            print("Geçersiz model: \(modelName). Desteklenenler: \(WhisperModel.allCases.map(\.rawValue).joined(separator: ", "))")
            return
        }
        
        print("=== Transkript Hub — Yerel İşlem Başlatılıyor ===")
        print("Girdi Dosyası: \(fileURL.path)")
        print("Model: \(selectedModel.rawValue)")
        print("Dil: \(language ?? "Otomatik Algılama")")
        
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
                print("\n[2/3] Model eksik, Hugging Face üzerinden yerel olarak indiriliyor (\(selectedModel.filename))...")
                modelURL = try await modelManager.downloadModel(selectedModel) { progress in
                    let percent = Int(progress * 100)
                    print("\rModel İndirme: %\(percent)", terminator: "")
                    fflush(stdout)
                }
                print("")
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
            
            if let detected = result.detectedLanguage {
                print("Algılanan Dil: \(detected)")
            }
            
            // Post-processing
            let postProcessor = TranscriptPostProcessor()
            let postOptions = PostProcessorOptions(insertTimestamps: insertTimestamps)
            let formattedText = postProcessor.process(segments: result.segments, options: postOptions)
            
            print("\n----------------- TRANSKRİPT ÇIKTISI -----------------")
            print(formattedText)
            print("------------------------------------------------------")
            
            // Save Output
            let targetURL: URL
            if let customOut = outputPath {
                targetURL = URL(fileURLWithPath: customOut)
            } else {
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                targetURL = fileURL.deletingLastPathComponent().appendingPathComponent("\(baseName).txt")
            }
            
            try formattedText.write(to: targetURL, atomically: true, encoding: .utf8)
            print("Çıktı başarıyla kaydedildi: \(targetURL.path)")
            
        } catch {
            print("\nTranskripsiyon hatası: \(error.localizedDescription)")
        }
    }
}
