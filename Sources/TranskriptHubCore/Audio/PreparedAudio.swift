import Foundation

public struct PreparedAudio: Sendable {
    /// 16 kHz mono Float32 audio samples
    public let samples: [Float]
    /// Total duration in seconds
    public let duration: Double
    
    public init(samples: [Float], duration: Double) {
        self.samples = samples
        self.duration = duration
    }
}
