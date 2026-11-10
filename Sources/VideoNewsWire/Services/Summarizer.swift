import Foundation
import FoundationModels

/// KI-Zusammenfassung komplett on-device mit Apples Foundation Models (Apple Intelligence).
///
/// Das lokale Modell hat ein kleines Kontextfenster (ca. 4 096 Tokens). Lange Transkripte werden
/// deshalb in Abschnitte zerlegt, einzeln verdichtet (map) und anschließend zusammengeführt (reduce).
enum Summarizer {
    /// `nil`, wenn das Modell verfügbar ist – sonst eine verständliche Begründung.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Dieser Mac unterstützt Apple Intelligence nicht (Apple Silicon erforderlich)."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence ist deaktiviert (Systemeinstellungen → Apple Intelligence & Siri)."
            case .modelNotReady:
                return "Das Apple-Intelligence-Modell wird noch geladen. Bitte später erneut versuchen."
            @unknown default:
                return "Apple Intelligence ist derzeit nicht verfügbar."
            }
        @unknown default:
            return "Apple Intelligence ist derzeit nicht verfügbar."
        }
    }

    /// Zeichen pro Abschnitt – lässt im 4K-Kontext Platz für Anweisungen und Antwort.
    private static let chunkLength = 6_000

    private static let noteInstructions = """
        Du fasst Abschnitte aus Transkripten von YouTube-Videos zusammen. \
        Antworte ausschließlich auf Deutsch, sachlich und knapp. \
        Gib nur Stichpunkte zurück, die jeweils mit "- " beginnen. \
        Erfinde nichts, was nicht im Text steht. Ignoriere Werbung, Sponsoren und Aufrufe zum Abonnieren.
        """

    private static let finalInstructions = """
        Du schreibst neutrale, kompakte Zusammenfassungen von YouTube-Videos auf Deutsch. \
        Keine Wertungen, keine Übertreibungen, keine Werbung, keine Aufforderungen. \
        Verwende keine Überschriften mit #. Erfinde nichts.
        """

    static func summarize(title: String, channel: String, text: String, isDescriptionOnly: Bool,
                          progress: @escaping @MainActor (String) -> Void) async throws -> String {
        do {
            let chunks = chunk(text)
            var notes = text

            if chunks.count > 1 {
                var parts: [String] = []
                for (index, part) in chunks.enumerated() {
                    try Task.checkCancellation()
                    await progress("Analysiere Abschnitt \(index + 1) von \(chunks.count)…")
                    parts.append(try await condense(part))
                }
                notes = parts.joined(separator: "\n")

                // Bei sehr langen Videos die Notizen in weiteren Runden verdichten.
                var round = 0
                while notes.count > chunkLength && round < 3 {
                    try Task.checkCancellation()
                    await progress("Verdichte Notizen…")
                    var merged: [String] = []
                    for part in chunk(notes) { merged.append(try await condense(part)) }
                    notes = merged.joined(separator: "\n")
                    round += 1
                }
            }

            try Task.checkCancellation()
            await progress("Schreibe Zusammenfassung…")
            let source = isDescriptionOnly
                ? "Videobeschreibung (kein Transkript verfügbar)"
                : (chunks.count > 1 ? "Notizen aus dem Transkript" : "Transkript")

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

    // MARK: - Helfer

    private static func finalSummary(title: String, channel: String, source: String, notes: String) async throws -> String {
        let prompt = """
            Video: "\(title)" von \(channel)
            Quelle: \(source)

            \(notes)

            Schreibe eine Zusammenfassung auf Deutsch in genau diesem Format:
            **Kurzfassung:** zwei bis drei Sätze.

            **Kernpunkte:**
            - drei bis sieben Stichpunkte
            """
        return try await respond(prompt, instructions: finalInstructions, maxTokens: 700)
    }

    /// Verdichtet einen Abschnitt zu Stichpunkten; teilt ihn bei Kontextüberlauf rekursiv.
    private static func condense(_ text: String) async throws -> String {
        do {
            return try await respond("Fasse diesen Abschnitt in höchstens sechs Stichpunkten zusammen:\n\n\(text)",
                                     instructions: noteInstructions, maxTokens: 350)
        } catch let error where isContextOverflow(error) && text.count > 1_000 {
            let middle = text.index(text.startIndex, offsetBy: text.count / 2)
            let first = try await condense(String(text[..<middle]))
            let second = try await condense(String(text[middle...]))
            return first + "\n" + second
        }
    }

    private static func respond(_ prompt: String, instructions: String, maxTokens: Int) async throws -> String {
        // Für jeden Schritt eine frische Session, damit sich kein Kontext ansammelt.
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
            return AppError("Apple Intelligence hat die Zusammenfassung aus Sicherheitsgründen abgelehnt.")
        case .unsupportedLanguageOrLocale:
            return AppError("Die Sprache dieses Videos wird von Apple Intelligence nicht unterstützt.")
        case .exceededContextWindowSize:
            return AppError("Der Text ist zu lang für das lokale Modell.")
        default:
            return error
        }
    }
}
