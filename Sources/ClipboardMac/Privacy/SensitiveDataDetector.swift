import Foundation

/// Heuristics for content that should never be stored in history:
/// tokens, keys, credit card numbers, and similar secrets.
enum SensitiveDataDetector {
    private static let patterns: [NSRegularExpression] = {
        let sources = [
            // JWT tokens
            #"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,
            // PEM private keys
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            // AWS access keys
            #"\bAKIA[0-9A-Z]{16}\b"#,
            // OpenAI / Stripe style secret keys
            #"\bsk-[A-Za-z0-9_-]{20,}\b"#,
            // GitHub tokens
            #"\bgh[pousr]_[A-Za-z0-9]{30,}\b"#,
            // Slack tokens
            #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#,
            // key=value style secrets
            #"(?i)\b(api[_-]?key|secret|password|passwd|token)\s*[:=]\s*\S{12,}"#
        ]
        return sources.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
    }()

    static func looksSensitive(_ text: String) -> Bool {
        // Only scan a bounded prefix; secrets are short and this keeps
        // large copies cheap.
        let sample = String(text.prefix(20_000))
        let range = NSRange(sample.startIndex..., in: sample)

        for pattern in patterns {
            if pattern.firstMatch(in: sample, range: range) != nil {
                return true
            }
        }

        return containsCreditCardNumber(sample)
    }

    /// 13–16 digit runs (possibly space/dash separated) that pass Luhn.
    private static func containsCreditCardNumber(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]?){13,19}\b"#) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        var found = false
        regex.enumerateMatches(in: text, range: range) { match, _, stop in
            guard let match = match, let matchRange = Range(match.range, in: text) else { return }
            let digits = text[matchRange].filter(\.isNumber)
            if (13...19).contains(digits.count), passesLuhn(String(digits)) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard let value = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }
}
