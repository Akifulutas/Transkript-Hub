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
            print("Unknown command: \(command)")
            printUsage()
        }
    }
    
    static func printUsage() {
        print("""
        Transkript Hub CLI v1.0 — Apple Silicon Native Transcription
        
        Usage:
          transkripthub-cli batch <url1> <url2> ... [options]
          transkripthub-cli youtube <youtube_url> [options]
          transkripthub-cli transcribe <audio_file> [options]
          transkripthub-cli tools [install | status]
          transkripthub-cli models [download <model_name> | list]
          transkripthub-cli version
        
        Batch Options:
          --file <file>     Text file containing YouTube links
          --model <name>    Model (tiny, base, small, medium, large-v3-turbo, large-v3-turbo-q5_0) [Default: tiny]
          --lang <code>     Language code (en, de, tr or auto) [Default: auto]
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
                    print("Error: Could not read file: \(filePath)")
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
                    print("Warning: Skipping invalid URL: \(arg)")
                }
                i += 1
            } else {
                i += 1
            }
        }
        
        guard !rawURLs.isEmpty else {
            print("Error: No valid video URLs found to process.")
            printUsage()
            return
        }
        
        guard let selectedModel = WhisperModel(rawValue: modelName) else {
            print("Invalid model: \(modelName).")
            return
        }
        
        print("=== Transkript Hub — Starting Batch Processing ===")
        print("Total Videos: \(rawURLs.count)")
        print("Model: \(selectedModel.rawValue)")
        print("Language: \(language ?? "Auto")")
        
        do {
            let database = try AppDatabase.makeShared()
            let jobManager = JobManager(database: database)
            
            // 1. Recover state
            try await jobManager.recoverState()
            
            // 2. Create batch
            let batch = try await jobManager.createYouTubeBatch(urls: rawURLs, language: language)
            print("Batch created (ID: \(batch.id))")
            
            // 3. Process with live updates
            let totalCount = rawURLs.count
            let result = try await jobManager.processBatch(batchID: batch.id, model: selectedModel) { job in
                let titleStr = job.title ?? job.externalID ?? "Unknown"
                print(" -> [Video \(job.sequence)/\(totalCount)] \(titleStr): \(job.state.uppercased())")
            }
            
            switch result {
            case .assembled(let outputURL, let isPartial):
                print("\n=======================================================")
                if isPartial {
                    print("⚠️ Partial Success: Some videos failed to download, but all successful transcripts were merged!")
                } else {
                    print("🎉 Success: All videos transcribed and assembled successfully!")
                }
                print("Consolidated Output File: \(outputURL.path)")
                print("Temporary audio files cleaned up.")
                print("=======================================================")
            case .waiting(let count):
                print("Processing still in progress, waiting videos: \(count)")
            case .empty:
                print("Error: No completed video transcripts found to assemble.")
            }
            
        } catch {
            print("\nBatch execution error: \(error.localizedDescription)")
        }
    }
    
    static func handleTools(arguments: [String]) async {
        let toolManager = ToolManager()
        let sub = arguments.first ?? "status"
        
        if sub == "status" {
            print("Managed Tools Status:")
            print(" - yt-dlp: \(toolManager.isYTDLPReady() ? "✅ Ready (\(toolManager.ytdlpExecutableURL.path))" : "⏳ Not installed")")
            print(" - deno:   \(toolManager.isDenoReady() ? "✅ Ready (\(toolManager.denoExecutableURL.path))" : "⏳ Not installed")")
            return
        }
        
        if sub == "install" {
            do {
                print("Downloading and configuring required tools...")
                try await toolManager.ensureToolsReady { message, ratio in
                    let percent = Int(ratio * 100)
                    print("\r[\(message)] \(percent)%", terminator: "")
                    fflush(stdout)
                }
                print("\n✅ All tools ready!")
            } catch {
                print("\n❌ Tool installation error: \(error.localizedDescription)")
            }
        }
    }
    
    static func handleYouTube(arguments: [String]) async {
        guard let urlStr = arguments.first, !urlStr.hasPrefix("-") else {
            print("Error: No YouTube video URL provided.")
            printUsage()
            return
        }
        
        guard let parsed = URLParser.parseSingle(urlStr) else {
            print("Error: Invalid YouTube URL: \(urlStr)")
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
            print("Invalid model: \(modelName).")
            return
        }
        
        print("=== Transkript Hub — Starting YouTube Processing ===")
        print("Video URL: \(parsed.canonicalURL) [ID: \(parsed.videoID)]")
        print("Model: \(selectedModel.rawValue)")
        
        // 1. Prepare Tools
        let toolManager = ToolManager()
        do {
            if !toolManager.isYTDLPReady() || !toolManager.isDenoReady() {
                print("\n[1/4] Downloading required YouTube tools...")
                try await toolManager.ensureToolsReady { msg, ratio in
                    let percent = Int(ratio * 100)
                    print("\r\(msg): \(percent)%", terminator: "")
                    fflush(stdout)
                }
                print("")
            } else {
                print("\n[1/4] YouTube tools ready.")
            }
        } catch {
            print("\nTool preparation error: \(error.localizedDescription)")
            return
        }
        
        // 2. Fetch Video Audio
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("TranskriptHub_Job_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        
        print("\n[2/4] Downloading audio and metadata...")
        let fetchedMedia: FetchedMedia
        let ytdlp = YTDLPClient(toolManager: toolManager)
        do {
            fetchedMedia = try await ytdlp.fetch(url: parsed.canonicalURL, into: workspace) { ratio in
                let percent = Int(ratio * 100)
                print("\rDownload Progress: \(percent)%", terminator: "")
                fflush(stdout)
            }
            print("\nVideo: \(fetchedMedia.metadata.title)")
            if let ch = fetchedMedia.metadata.channel {
                print("Channel: \(ch)")
            }
        } catch {
            print("\nYouTube download error: \(error.localizedDescription)")
            return
        }
        
        // 3. Decode Audio
        print("\n[3/4] Decoding audio (AVFoundation)...")
        let decoder = AudioDecoder()
        let preparedAudio: PreparedAudio
        do {
            preparedAudio = try decoder.decode(fileURL: fetchedMedia.localAudioURL)
            let durStr = String(format: "%.1f", preparedAudio.duration)
            print("Audio decoded (Duration: \(durStr)s)")
        } catch {
            print("Audio decode error: \(error.localizedDescription)")
            return
        }
        
        // 4. Transcribe with Metal
        print("\n[4/4] Transcribing with Metal GPU acceleration...")
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
                print("\rTranscription Progress: \(percent)%", terminator: "")
                fflush(stdout)
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print(String(format: "\nTranscription completed (%.2fs)", elapsed))
            
            // Post-processing
            let postProcessor = TranscriptPostProcessor()
            let formattedText = postProcessor.process(
                segments: result.segments,
                options: PostProcessorOptions(insertTimestamps: insertTimestamps)
            )
            
            // Save Output using OutputWriter (Title.txt)
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
            print("\n🎉 Completed successfully!")
            print("Output File: \(targetURL.path)")
            
        } catch {
            print("\nProcessing error: \(error.localizedDescription)")
        }
    }
    
    static func handleModels(arguments: [String]) async {
        let manager = ModelManager()
        if arguments.first == "list" || arguments.isEmpty {
            print("Supported models and download status:")
            for m in WhisperModel.allCases {
                let downloaded = manager.isModelDownloaded(m)
                let status = downloaded ? "✅ Downloaded" : "⏳ Not downloaded"
                print(" - \(m.rawValue) (\(m.filename)) -> \(status)")
            }
            print("\nModels directory: \(manager.modelsDirectory.path)")
            return
        }
        
        if arguments.first == "download", arguments.count >= 2 {
            let modelName = arguments[1]
            guard let model = WhisperModel(rawValue: modelName) else {
                print("Invalid model name: \(modelName).")
                return
            }
            do {
                print("Downloading model \(model.rawValue)...")
                let path = try await manager.downloadModel(model) { progress in
                    let percent = Int(progress * 100)
                    print("\rProgress: \(percent)%", terminator: "")
                    fflush(stdout)
                }
                print("\nModel ready: \(path.path)")
            } catch {
                print("\nDownload error: \(error.localizedDescription)")
            }
        }
    }
    
    static func handleTranscribe(arguments: [String]) async {
        guard let firstArg = arguments.first, !firstArg.hasPrefix("-") else {
            print("Error: No audio file specified to transcribe.")
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
            print("Invalid model: \(modelName).")
            return
        }
        
        print("=== Transkript Hub — Starting Local Transcription ===")
        print("Input File: \(fileURL.path)")
        print("Model: \(selectedModel.rawValue)")
        
        // 1. Audio Decoding
        print("\n[1/3] Decoding audio (AVFoundation 16 kHz Mono PCM)...")
        let decoder = AudioDecoder()
        let preparedAudio: PreparedAudio
        do {
            preparedAudio = try decoder.decode(fileURL: fileURL)
            let durationStr = String(format: "%.2f", preparedAudio.duration)
            print("Audio decoded successfully. Duration: \(durationStr)s, Sample Count: \(preparedAudio.samples.count)")
        } catch {
            print("Audio decode error: \(error.localizedDescription)")
            return
        }
        
        // 2. Model Preparation
        let modelManager = ModelManager()
        let modelURL: URL
        do {
            if !modelManager.isModelDownloaded(selectedModel) {
                print("\n[2/3] Downloading model (\(selectedModel.filename))...")
                modelURL = try await modelManager.downloadModel(selectedModel)
            } else {
                modelURL = modelManager.localURL(for: selectedModel)
                print("\n[2/3] Model already available: \(modelURL.lastPathComponent)")
            }
        } catch {
            print("Model preparation error: \(error.localizedDescription)")
            return
        }
        
        // 3. Transcription
        print("\n[3/3] Transcribing with Metal GPU acceleration...")
        do {
            let engine = try WhisperCppEngine(modelPath: modelURL.path)
            let options = TranscriptionOptions(language: language)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try await engine.transcribe(preparedAudio, options: options) { progress in
                let percent = Int(progress * 100)
                print("\rTranscription Progress: \(percent)%", terminator: "")
                fflush(stdout)
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print(String(format: "\nTranscription completed in %.2f seconds.", elapsed))
            
            // Post-processing
            let postProcessor = TranscriptPostProcessor()
            let postOptions = PostProcessorOptions(insertTimestamps: insertTimestamps)
            let formattedText = postProcessor.process(segments: result.segments, options: postOptions)
            
            print("\n----------------- TRANSCRIPT OUTPUT -----------------")
            print(formattedText)
            print("-----------------------------------------------------")
            
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
            print("Output saved successfully: \(targetURL.path)")
            
        } catch {
            print("\nTranscription error: \(error.localizedDescription)")
        }
    }
}
