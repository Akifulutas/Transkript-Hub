import Foundation

public enum SRTFormatter: Sendable {
    private static let minimumCueDuration: Double = 0.1

    /// Formats transcript segments into standards-compliant SubRip (.srt) text.
    /// - Filters empty/whitespace-only segments before assigning 1-based contiguous cue indices.
    /// - Wraps lines naturally at word boundaries up to `maxLineLength` (default 42) and `maxLines` (default 2).
    /// - Splits segments exceeding `maxLines` into sequential cues with distributed timestamps so zero words are dropped.
    public static func format(
        segments: [Segment],
        maxLineLength: Int = 42,
        maxLines: Int = 2
    ) -> String {
        guard !segments.isEmpty else { return "" }

        let safeMaxLineLength = max(1, maxLineLength)
        let safeMaxLines = max(1, maxLines)

        var blocks: [String] = []
        var cueIndex = 1

        for segment in segments {
            let normalizedText = normalizeWhitespace(segment.text)
            guard !normalizedText.isEmpty else { continue }

            let safeStart = segment.start.isFinite ? max(0.0, segment.start) : 0.0
            let rawEnd = segment.end.isFinite ? max(0.0, segment.end) : safeStart
            let safeEnd = max(rawEnd, safeStart + minimumCueDuration)

            let cuePayloads = splitIntoCuePayloads(
                text: normalizedText,
                maxLineLength: safeMaxLineLength,
                maxLines: safeMaxLines
            )

            guard !cuePayloads.isEmpty else { continue }

            if cuePayloads.count == 1 {
                let startStr = formatTimestamp(safeStart)
                let endStr = formatTimestamp(safeEnd)
                blocks.append("\(cueIndex)\n\(startStr) --> \(endStr)\n\(cuePayloads[0])")
                cueIndex += 1
            } else {
                let startMs = Int((safeStart * 1000.0).rounded())
                let rawEndMs = Int((safeEnd * 1000.0).rounded())
                let totalEndMs = max(rawEndMs, startMs + cuePayloads.count)
                let weights = cuePayloads.map { max(1, $0.count) }
                var remainingWeight = weights.reduce(0, +)
                var currentStartMs = startMs

                for (idx, payload) in cuePayloads.enumerated() {
                    let remainingCues = cuePayloads.count - idx
                    let cueEndMs: Int
                    if idx == cuePayloads.count - 1 {
                        cueEndMs = totalEndMs
                    } else {
                        let remainingDurationMs = totalEndMs - currentStartMs
                        let maxAllowedEndMs = totalEndMs - (remainingCues - 1)
                        let share = Int((Double(remainingDurationMs) * Double(weights[idx]) / Double(max(1, remainingWeight))).rounded())
                        let proposedEndMs = currentStartMs + max(1, share)
                        cueEndMs = min(maxAllowedEndMs, max(currentStartMs + 1, proposedEndMs))
                    }
                    let startStr = formatMilliseconds(currentStartMs)
                    let endStr = formatMilliseconds(cueEndMs)
                    blocks.append("\(cueIndex)\n\(startStr) --> \(endStr)\n\(payload)")
                    cueIndex += 1
                    currentStartMs = cueEndMs
                    remainingWeight -= weights[idx]
                }
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    /// Formats seconds as `HH:mm:ss,SSS` using total integer millisecond rounding.
    public static func formatTimestamp(_ seconds: Double) -> String {
        let clamped = (seconds.isFinite && seconds > 0.0) ? seconds : 0.0
        let totalMilliseconds = Int((clamped * 1000.0).rounded())
        return formatMilliseconds(totalMilliseconds)
    }

    private static func formatMilliseconds(_ totalMilliseconds: Int) -> String {
        let clampedMs = max(0, totalMilliseconds)
        let ms = clampedMs % 1000
        let totalSeconds = clampedMs / 1000
        let secs = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, ms)
    }

    // MARK: - Internal Helpers

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }

    private static func splitIntoCuePayloads(
        text: String,
        maxLineLength: Int,
        maxLines: Int
    ) -> [String] {
        if text.count <= maxLineLength {
            return [text]
        }

        let rawWords = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let tokens = rawWords.flatMap { breakOversizedWord($0, maxLineLength: maxLineLength) }
        guard !tokens.isEmpty else { return [] }

        // If 2-line max and everything fits in 2 lines, compute a balanced natural split
        if maxLines == 2, let balanced = balancedTwoLineSplit(tokens: tokens, maxLineLength: maxLineLength) {
            return [balanced.joined(separator: "\n")]
        }

        // Greedy wrap into lines <= maxLineLength
        let lines = greedyWrap(tokens: tokens, maxLineLength: maxLineLength)
        guard !lines.isEmpty else { return [] }

        // Group lines into cues of at most `maxLines` lines each
        var payloads: [String] = []
        var lineIdx = 0
        while lineIdx < lines.count {
            let endIdx = min(lines.count, lineIdx + maxLines)
            let chunk = lines[lineIdx..<endIdx]
            payloads.append(chunk.joined(separator: "\n"))
            lineIdx = endIdx
        }
        return payloads
    }

    private static func breakOversizedWord(_ word: String, maxLineLength: Int) -> [String] {
        guard word.count > maxLineLength else { return [word] }

        // First try splitting after hyphens or slashes so compound words break cleanly
        var pieces: [String] = []
        var current = ""
        for ch in word {
            current.append(ch)
            if (ch == "-" || ch == "/") && !current.isEmpty {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }

        // Coalesce small hyphenated parts up to maxLineLength, and slice any piece still > maxLineLength
        var normalizedTokens: [String] = []
        var buffer = ""
        for piece in pieces {
            let workPiece: String
            if piece.count > maxLineLength {
                if !buffer.isEmpty {
                    if buffer.count == 1 {
                        workPiece = buffer + piece
                        buffer = ""
                    } else {
                        normalizedTokens.append(buffer)
                        buffer = ""
                        workPiece = piece
                    }
                } else {
                    workPiece = piece
                }
            } else if !buffer.isEmpty && buffer.count == 1 && buffer.count + piece.count > maxLineLength {
                workPiece = buffer + piece
                buffer = ""
            } else {
                workPiece = piece
            }

            if workPiece.count > maxLineLength {
                var start = workPiece.startIndex
                while start < workPiece.endIndex {
                    let end = workPiece.index(start, offsetBy: maxLineLength, limitedBy: workPiece.endIndex) ?? workPiece.endIndex
                    let chunk = String(workPiece[start..<end])
                    if end < workPiece.endIndex {
                        normalizedTokens.append(chunk)
                    } else {
                        buffer = chunk
                    }
                    start = end
                }
            } else if buffer.isEmpty {
                buffer = workPiece
            } else if buffer.count + workPiece.count <= maxLineLength {
                buffer += workPiece
            } else {
                normalizedTokens.append(buffer)
                buffer = workPiece
            }
        }
        if !buffer.isEmpty {
            normalizedTokens.append(buffer)
        }

        return normalizedTokens
    }

    private static func balancedTwoLineSplit(tokens: [String], maxLineLength: Int) -> [String]? {
        guard tokens.count >= 2 else { return nil }

        var bestLines: [String]? = nil
        var bestScore = Int.max

        for splitIdx in 1..<tokens.count {
            let line1 = tokens[0..<splitIdx].joined(separator: " ")
            if line1.count > maxLineLength { break }

            let line2 = tokens[splitIdx..<tokens.count].joined(separator: " ")
            if line2.count > maxLineLength { continue }

            var score = abs(line1.count - line2.count)
            if let lastChar = line1.last, [",", ";", ":", ".", "!", "?", "-"].contains(lastChar) {
                score -= 6
            }
            if score < bestScore {
                bestScore = score
                bestLines = [line1, line2]
            }
        }

        return bestLines
    }

    private static func greedyWrap(tokens: [String], maxLineLength: Int) -> [String] {
        var lines: [String] = []
        var currentLine = ""

        for token in tokens {
            if currentLine.isEmpty {
                currentLine = token
            } else if currentLine.count + 1 + token.count <= maxLineLength {
                currentLine += " " + token
            } else {
                lines.append(currentLine)
                currentLine = token
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }
}
