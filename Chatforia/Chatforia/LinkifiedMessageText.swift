import Foundation
import SwiftUI

struct LinkifiedMessageText: View {
    let text: String

    var body: some View {
        Text(Self.makeAttributedText(from: text))
    }

    private static func makeAttributedText(
        from text: String
    ) -> AttributedString {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return AttributedString(text)
        }

        let fullRange = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )

        let matches = detector.matches(
            in: text,
            options: [],
            range: fullRange
        )

        guard !matches.isEmpty else {
            return AttributedString(text)
        }

        var result = AttributedString()
        var currentIndex = text.startIndex

        for match in matches {
            guard
                let stringRange = Range(match.range, in: text)
            else {
                continue
            }

            if currentIndex < stringRange.lowerBound {
                let precedingText =
                    String(text[currentIndex..<stringRange.lowerBound])

                result += AttributedString(precedingText)
            }

            let visibleURL = String(text[stringRange])

            if let url = normalizedWebURL(
                matchURL: match.url,
                visibleText: visibleURL
            ) {
                var linkedText = AttributedString(visibleURL)
                linkedText.link = url
                linkedText.underlineStyle = .single
                result += linkedText
            } else {
                result += AttributedString(visibleURL)
            }

            currentIndex = stringRange.upperBound
        }

        if currentIndex < text.endIndex {
            let remainingText =
                String(text[currentIndex..<text.endIndex])

            result += AttributedString(remainingText)
        }

        return result
    }

    private static func normalizedWebURL(
        matchURL: URL?,
        visibleText: String
    ) -> URL? {
        if let matchURL,
           let scheme = matchURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return matchURL
        }

        let candidate: String

        if visibleText.lowercased().hasPrefix("www.") {
            candidate = "https://\(visibleText)"
        } else {
            candidate = visibleText
        }

        guard
            let url = URL(string: candidate),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        return url
    }
}
