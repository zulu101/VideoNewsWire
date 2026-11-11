import Foundation
import FoundationModels

/// AI summaries entirely on-device with Apple's Foundation Models (Apple Intelligence).
///
/// The local model has a small context window (about 4,096 tokens). Long transcripts are therefore
/// split into sections, condensed one by one (map) and then combined (reduce).
/// Summaries are written in the app's current language (English, or German on German systems).
enum Summarizer {
    /// `nil` if the model is available, otherwise a human-readable reason.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return String(localized: "This Mac doesn’t support Apple Intelligence (Apple silicon required).")
            case .appleIntelligenceNotEnabled:
                return String(localized: "Apple Intelligence is turned off (System Settings → Apple Intelligence & Siri).")
            case .modelNotReady:
                return String(localized: "The Apple Intelligence model is still loading. Please try again later.")
            @unknown default:
                return String(localized: "Apple Intelligence is currently unavailable.")
            }
        @unknown default:
            return String(localized: "Apple Intelligence is currently unavailable.")
        }
    }

    /// Language code of the app's current localization ("en", "de"), used for summaries and subtitles.
    static var languageCode: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        let code = String(preferred.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
        return code.isEmpty || code == "base" ? "en" : code
    }

    /// English name of the output language, e.g. "German", for the model instructions.
    private static var languageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English"
    }

    /// Characters per section; leaves room in the 4K context for instructions and the answer.
    private static let chunkLength = 6_000

    private static var noteInstructions: String {
        """
        You summarize sections of YouTube video transcripts. \
        Always answer in \(languageName), factually and concisely. \
        Return only bullet points, each starting with "- ". \
        Do not invent anything that is not in the text. Ignore ads, sponsors and calls to subscribe.
        """
    }

    private static var finalInstructions: String {
        """
        You write neutral, compact summaries of YouTube videos in \(languageName). \
        No judgments, no exaggeration, no advertising, no calls to action. \
        Do not use headings with #. Do not invent anything.
        """
    }

    static func summarize(title: String, channel: String, text: String, isDescriptionOnly: Bool,
                          progress: @escaping @MainActor (String) -> Void) async throws -> String {
        do {
            let chunks = chunk(text)
            var notes = text

            if chunks.count > 1 {
                var parts: [String] = []
                for (index, part) in chunks.enumerated() {
                    try Task.checkCancellation()
                    await progress(String(localized: "Analyzing section \(index + 1) of \(chunks.count)…"))
                    parts.append(try await condense(part))
                }
                notes = parts.joined(separator: "\n")

                // For very long videos, condense the notes in further rounds.
                var round = 0
                while notes.count > chunkLength && round < 3 {
                    try Task.checkCancellation()
                    await progress(String(localized: "Condensing notes…"))
                    var merged: [String] = []
                    for part in chunk(notes) { merged.append(try await condense(part)) }
                    notes = merged.joined(separator: "\n")
                    round += 1
                }
            }

            try Task.checkCancellation()
            await progress(String(localized: "Writing summary…"))
            let source = isDescriptionOnly
                ? "video description (no transcript available)"
                : (chunks.count > 1 ? "notes taken from the transcript" : "transcript")

            do {
                return try await finalSummary(title: title, channel: channel, source: source, notes: notes)
            } catch let error where isContextOverflow(error) {
                let condensed = try await condense(notes)
                return try await finalSummary(title: title, channel: channel, source: source, notes: condensed)
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw friendly(error)
        }
    }

    // MARK: - Helpers

    private static func finalSummary(title: String, channel: String, source: String, notes: String) async throws -> String {
        let summaryLabel = String(localized: "In brief")
        let keyPointsLabel = String(localized: "Key points")
        let prompt = """
            Video: "\(title)" by \(channel)
            Source: \(source)

            \(notes)

            Write a summary in \(languageName) in exactly this format:
            **\(summaryLabel):** two to three sentences.

            **\(keyPointsLabel):**
            - three to seven bullet points
            """
        return try await respond(prompt, instructions: finalInstructions, maxTokens: 700)
    }

    /// Condenses a section into bullet points; splits it recursively if the context overflows.
    private static func condense(_ text: String) async throws -> String {
        do {
            return try await respond("Summarize this section in at most six bullet points:\n\n\(text)",
                                     instructions: noteInstructions, maxTokens: 350)
        } catch let error where isContextOverflow(error) && text.count > 1_000 {
            let middle = text.index(text.startIndex, offsetBy: text.count / 2)
            let first = try await condense(String(text[..<middle]))
            let second = try await condense(String(text[middle...]))
            return first + "\n" + second
        }
    }

    private static func respond(_ prompt: String, instructions: String, maxTokens: Int) async throws -> String {
        // A fresh session for every step, so no context piles up.
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: maxTokens)
        let response = try await session.respond(to: prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chunk(_ text: String) -> [String] {
        guard text.count > chunkLength else { return [text] }
        var chunks: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if current.count + word.count + 1 > chunkLength, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " " + word
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func isContextOverflow(_ error: Error) -> Bool {
        if let generationError = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generationError {
            return true
        }
        return false
    }

    private static func friendly(_ error: LanguageModelSession.GenerationError) -> Error {
        switch error {
        case .guardrailViolation:
            return AppError(String(localized: "Apple Intelligence declined to summarize this video for safety reasons."))
        case .unsupportedLanguageOrLocale:
            return AppError(String(localized: "This video’s language isn’t supported by Apple Intelligence."))
        case .exceededContextWindowSize:
            return AppError(String(localized: "The text is too long for the local model."))
        default:
            return error
        }
    }
}
