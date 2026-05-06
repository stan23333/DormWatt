//
//  BalanceParser.swift
//  DormWatt
//

import Foundation

protocol BalanceParser {
    func parseBalance(from text: String) throws -> Double
}

struct RegexBalanceParser: BalanceParser {
    private let patterns = [
        #"(?i)(?:剩余电费|剩余电量|余额|剩余金额|balance|remaining)\s*[:：]?\s*([+-]?\d+(?:\.\d+)?)"#,
        #"([+-]?\d+(?:\.\d+)?)\s*(?:元|度)?"#
    ]

    func parseBalance(from text: String) throws -> Double {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for pattern in patterns {
            if let value = firstNumber(in: normalizedText, pattern: pattern) {
                return value
            }
        }

        throw DormWattError.parseFailure(normalizedText)
    }

    private func firstNumber(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        let captureIndex = match.numberOfRanges > 1 ? 1 : 0
        guard let captureRange = Range(match.range(at: captureIndex), in: text) else {
            return nil
        }

        return Double(text[captureRange])
    }
}
