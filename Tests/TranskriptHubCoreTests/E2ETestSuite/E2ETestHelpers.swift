import Foundation
import Testing
@testable import TranskriptHubCore

enum E2ETestHelpers {
    static let defaultSampleRate: Double = 16000.0

    // MARK: - Deterministic Synthetic Audio Generators

    static func makeSilence(seconds: Double, sampleRate: Double = defaultSampleRate) -> [Float] {
        guard seconds.isFinite, seconds > 0, sampleRate.isFinite, sampleRate > 0 else { return [] }
        let count = max(0, Int((seconds * sampleRate).rounded()))
        return [Float](repeating: 0.0, count: count)
    }

    /// Generates a deterministic sine wave with exact target RMS amplitude.
    /// For a sinusoid, peak = targetRMS * sqrt(2).
    static func makeSineWave(
        seconds: Double,
        frequency: Double = 1000.0,
        targetRMS: Float = 0.35,
        sampleRate: Double = defaultSampleRate
    ) -> [Float] {
        guard seconds.isFinite, seconds > 0,
              sampleRate.isFinite, sampleRate > 0,
              frequency.isFinite, targetRMS.isFinite, targetRMS >= 0 else { return [] }
        let count = max(0, Int((seconds * sampleRate).rounded()))
        guard count > 0 else { return [] }
        let amplitude = targetRMS * Float(2.0).squareRoot()
        var samples = [Float](repeating: 0.0, count: count)
        let angularFreq = 2.0 * Double.pi * frequency / sampleRate
        for i in 0..<count {
            samples[i] = amplitude * Float(sin(angularFreq * Double(i)))
        }
        return samples
    }

    /// Generates deterministic broadband noise with exact target RMS using SplitMix64 PRNG.
    static func makeDeterministicNoise(
        seconds: Double,
        targetRMS: Float,
        seed: UInt64 = 0x5452414E534B5249,
        sampleRate: Double = defaultSampleRate
    ) -> [Float] {
        guard seconds.isFinite, seconds > 0,
              sampleRate.isFinite, sampleRate > 0,
              targetRMS.isFinite, targetRMS >= 0 else { return [] }
        let count = max(0, Int((seconds * sampleRate).rounded()))
        guard count > 0 else { return [] }

        var state = seed
        func nextUniform() -> Float {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            let unit = Double(z >> 11) / Double(1 << 53)
            return Float(unit * 2.0 - 1.0)
        }

        var samples = [Float](repeating: 0.0, count: count)
        var sumSq: Double = 0.0
        for i in 0..<count {
            let v = nextUniform()
            samples[i] = v
            sumSq += Double(v) * Double(v)
        }

        let currentRMS = Float((sumSq / Double(count)).squareRoot())
        guard currentRMS > 0 else { return samples }
        let scale = targetRMS / currentRMS
        for i in 0..<count {
            samples[i] *= scale
        }
        return samples
    }

    static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        let count = max(a.count, b.count)
        var out = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            let va = i < a.count ? a[i] : 0.0
            let vb = i < b.count ? b[i] : 0.0
            out[i] = max(-1.0, min(1.0, va + vb))
        }
        return out
    }

    // MARK: - CLI Process Runner

    struct CLIOutput: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var combinedOutput: String {
            [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    static func packageRootURL(from filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static func cliBinaryURL() -> URL? {
        var candidates: [URL] = []

        // 1. Sibling of the active .xctest bundle (matches Debug, Release, and --scratch-path)
        let bundleDir = Bundle(for: E2EBundleToken.self).bundleURL.deletingLastPathComponent()
        candidates.append(bundleDir.appendingPathComponent("transkripthub-cli"))

        // 2. Sibling / nearby build directory of CommandLine.arguments[0]
        if let arg0 = CommandLine.arguments.first, !arg0.isEmpty {
            let arg0URL = URL(fileURLWithPath: arg0).resolvingSymlinksInPath()
            var dir = arg0URL.deletingLastPathComponent()
            for _ in 0..<4 {
                candidates.append(dir.appendingPathComponent("transkripthub-cli"))
                dir = dir.deletingLastPathComponent()
            }
        }

        // 3. Standard SwiftPM / SwiftBuild product locations under package root
        let root = packageRootURL()
        let isReleaseBundle = bundleDir.path.localizedCaseInsensitiveContains("/release")
        let debugPaths = [
            ".build/debug/transkripthub-cli",
            ".build/out/Products/Debug/transkripthub-cli",
            ".build/arm64-apple-macosx/debug/transkripthub-cli",
            ".build/x86_64-apple-macosx/debug/transkripthub-cli"
        ]
        let releasePaths = [
            ".build/release/transkripthub-cli",
            ".build/out/Products/Release/transkripthub-cli",
            ".build/arm64-apple-macosx/release/transkripthub-cli",
            ".build/x86_64-apple-macosx/release/transkripthub-cli"
        ]
        let orderedPaths = isReleaseBundle ? (releasePaths + debugPaths) : (debugPaths + releasePaths)
        for relPath in orderedPaths {
            candidates.append(root.appendingPathComponent(relPath))
        }

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func runCLI(_ arguments: [String]) throws -> CLIOutput {
        let binaryURL = try #require(
            cliBinaryURL(),
            "transkripthub-cli binary not found. Run `swift build --product transkripthub-cli` before running CLI tests."
        )

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        process.currentDirectoryURL = packageRootURL()

        return try runProcessAndDrain(process)
    }

    static func runProcessAndDrain(_ process: Process) throws -> CLIOutput {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outBox = PipeDataBox()
        let errBox = PipeDataBox()
        let outHandleBox = FileHandleBox(outPipe.fileHandleForReading)
        let errHandleBox = FileHandleBox(errPipe.fileHandleForReading)
        let drainGroup = DispatchGroup()

        try process.run()

        // Drain stdout and stderr concurrently on background queues before waitUntilExit()
        // so outputs exceeding the 64 KB OS pipe buffer never deadlock the child process.
        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBox.store(outHandleBox.handle.readDataToEndOfFile())
            drainGroup.leave()
        }

        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.store(errHandleBox.handle.readDataToEndOfFile())
            drainGroup.leave()
        }

        process.waitUntilExit()
        drainGroup.wait()

        return CLIOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: outBox.load(), encoding: .utf8) ?? "",
            stderr: String(data: errBox.load(), encoding: .utf8) ?? ""
        )
    }
}

private final class E2EBundleToken {}

private final class PipeDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.withLock { storage = data }
    }

    func load() -> Data {
        lock.withLock { storage }
    }
}

private final class FileHandleBox: @unchecked Sendable {
    let handle: FileHandle
    init(_ handle: FileHandle) {
        self.handle = handle
    }
}

// MARK: - Deterministic Mock Transcription Engine

actor MockTranscriptionEngine: TranscriptionEngine {
    private var _capturedOptions: [TranscriptionOptions] = []
    private let segmentsToReturn: [Segment]
    private let detectedLanguage: String?

    init(segments: [Segment], detectedLanguage: String? = "de") {
        self.segmentsToReturn = segments
        self.detectedLanguage = detectedLanguage
    }

    var capturedOptions: [TranscriptionOptions] {
        _capturedOptions
    }

    func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)?,
        onSegment: (@Sendable (Segment) -> Void)?,
        cancellationToken: TranscriptionCancellationToken?
    ) async throws -> TranscriptResult {
        if cancellationToken?.isCancelled == true {
            throw CancellationError()
        }
        guard !audio.samples.isEmpty else {
            throw WhisperCppError.emptyAudio
        }

        _capturedOptions.append(options)

        for (idx, seg) in segmentsToReturn.enumerated() {
            if cancellationToken?.isCancelled == true {
                throw CancellationError()
            }
            onSegment?(seg)
            progress?(Double(idx + 1) / Double(max(1, segmentsToReturn.count)))
        }
        progress?(1.0)
        return TranscriptResult(segments: segmentsToReturn, detectedLanguage: detectedLanguage)
    }
}

final class AtomicBoolFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    func setTrue() {
        lock.withLock { _value = true }
    }

    var value: Bool {
        lock.withLock { _value }
    }
}
