import Foundation

struct ReaderDocument: Codable, Identifiable {
    var id = UUID()
    var title: String
    var sourceURL: String?
    var pages: [String]
    var page = 0
    var position: TimeInterval = 0
    var speed: Float = 1
    var updated = Date()
}

enum ReaderText {
    static func cleanImported(_ text: String) -> String {
        var cleaned = text
        let replacements: [(String, String)] = [
            ("(?m)^[ \\t]*(```|~~~)[^\\n]*\\n?", ""),
            ("!\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("(?m)^[ \\t]{0,3}#{1,6}[ \\t]+", ""),
            ("(?m)^[ \\t]*>[ \\t]?", ""),
            ("(?m)^[ \\t]*[-+*][ \\t]+", ""),
            ("(?m)^[ \\t]*\\d+[.)][ \\t]+", ""),
            ("(?m)^[ \\t]*(?:(?:\\*[ \\t]*){3,}|(?:-[ \\t]*){3,}|(?:_[ \\t]*){3,})[ \\t]*$", ""),
            ("(?<!\\\\)(\\*{1,3}|_{1,2}|~~)(?=\\S)(.+?)(?<=\\S)\\1", "$2"),
            ("(?<!\\\\)`([^`]+)`", "$1")
        ]
        for (pattern, replacement) in replacements {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return cleaned
    }

    /// Preserve every character; prefer sentence endings, then whitespace.
    static func chunks(_ text: String, limit: Int = 3_000) -> [String] {
        precondition(limit > 0)
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let maximum = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            var end = maximum
            if maximum < text.endIndex {
                let candidate = text[start..<maximum]
                let halfway = candidate.index(candidate.startIndex, offsetBy: candidate.count / 2)
                let tail = candidate[halfway...]
                if let boundary = tail.lastIndex(where: { ".!?。！？\n".contains($0) }) {
                    end = text.index(after: boundary)
                } else if let boundary = candidate.lastIndex(where: { $0.isWhitespace }) {
                    end = text.index(after: boundary)
                }
            }
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }

    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            if let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(sentence)
            }
        }
        return result.isEmpty ? [text] : result
    }
}

struct ReaderTiming: Codable, Equatable {
    let text: String?
    let start: Double?
    let duration: Double?
    let end: Double?
    var endTime: Double { end ?? (start ?? 0) + (duration ?? 0) }
}

struct ReaderTimings: Codable {
    var wordTimings: [ReaderTiming]?
    var sentenceTimings: [ReaderTiming]?
    var verseTimings: [ReaderTiming]?
    var allUrl: String?
    var sentencesUrl: String?
}

/// Match timing text sequentially against the original page, without rewriting it.
/// Repeated sentences therefore map to distinct ranges; an unmatched span is skipped.
struct ReaderSpan: Identifiable {
    let id: Int
    let range: Range<String.Index>
    let start: Double
    let end: Double

    static func map(_ timings: [ReaderTiming], to text: String) -> [ReaderSpan] {
        var cursor = text.startIndex
        return timings.enumerated().compactMap { index, timing in
            guard let start = timing.start, start.isFinite, timing.endTime.isFinite,
                  start >= 0, timing.endTime >= start,
                  let value = timing.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return nil }
            // AudioVix collapses whitespace when building its timing text.
            let pattern = value.split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
            guard let range = text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive], range: cursor..<text.endIndex)
                ?? text.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: cursor..<text.endIndex)
            else { return nil }
            cursor = range.upperBound
            return ReaderSpan(id: index, range: range, start: start, end: timing.endTime)
        }
    }
}
