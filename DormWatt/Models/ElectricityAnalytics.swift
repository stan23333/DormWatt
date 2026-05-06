//
//  ElectricityAnalytics.swift
//  DormWatt
//

import Foundation

enum ElectricityTimeRange: String, CaseIterable, Identifiable, Codable {
    case lastHour
    case last3Hours
    case last12Hours
    case lastDay
    case weekToDate
    case monthToDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastHour:
            return "Past 1 hour"
        case .last3Hours:
            return "Past 3 hours"
        case .last12Hours:
            return "Past 12 hours"
        case .lastDay:
            return "Past day"
        case .weekToDate:
            return "This week"
        case .monthToDate:
            return "This month"
        }
    }

    var shortTitle: String {
        switch self {
        case .lastHour:
            return "1H"
        case .last3Hours:
            return "3H"
        case .last12Hours:
            return "12H"
        case .lastDay:
            return "1D"
        case .weekToDate:
            return "Week"
        case .monthToDate:
            return "Month"
        }
    }

    func startDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .lastHour:
            return calendar.date(byAdding: .hour, value: -1, to: now) ?? now
        case .last3Hours:
            return calendar.date(byAdding: .hour, value: -3, to: now) ?? now
        case .last12Hours:
            return calendar.date(byAdding: .hour, value: -12, to: now) ?? now
        case .lastDay:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .weekToDate:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            components.weekday = 2
            return calendar.date(from: components) ?? now
        case .monthToDate:
            let components = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: components) ?? now
        }
    }
}

enum ElectricityAnalytics {
    static func sorted(_ records: [ElectricityRecord]) -> [ElectricityRecord] {
        records.sorted { $0.timestamp < $1.timestamp }
    }

    static func records(
        in range: ElectricityTimeRange,
        from records: [ElectricityRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ElectricityRecord] {
        let sortedRecords = sorted(records)
        let startDate = range.startDate(from: now, calendar: calendar)
        return sortedRecords.filter { $0.timestamp >= startDate && $0.timestamp <= now }
    }

    static func consumption(
        in range: ElectricityTimeRange,
        from records: [ElectricityRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let sortedRecords = sorted(records)
        let startDate = range.startDate(from: now, calendar: calendar)
        let rangeRecords = sortedRecords.filter { $0.timestamp >= startDate && $0.timestamp <= now }

        guard rangeRecords.count > 1 else {
            return 0
        }

        return zip(rangeRecords, rangeRecords.dropFirst()).reduce(0) { total, pair in
            let drop = pair.0.balance - pair.1.balance
            return total + max(0, drop)
        }
    }

    static func isLowBalance(record: ElectricityRecord?, threshold: Double) -> Bool {
        guard let record else {
            return false
        }
        return record.balance <= threshold
    }

    static func mockRecords(now: Date = Date(), calendar: Calendar = .current) -> [ElectricityRecord] {
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let points = max(1, Int(now.timeIntervalSince(start) / 900))
        var records: [ElectricityRecord] = []
        var balance = 38.0

        for index in 0...points {
            guard let timestamp = calendar.date(byAdding: .minute, value: index * 15, to: start) else {
                continue
            }

            if index > 0 {
                let hour = calendar.component(.hour, from: timestamp)
                let dailyRhythm = hour >= 18 || hour <= 1 ? 0.034 : 0.014
                let wave = (sin(Double(index) / 9.0) + 1.0) * 0.004
                balance -= dailyRhythm + wave
            }

            if balance < 7.0 && index % 377 == 0 {
                balance += 28.0
            }

            balance = min(max(balance, 2.2), 48.0)
            let roundedBalance = (balance * 100).rounded() / 100
            records.append(ElectricityRecord(
                balance: roundedBalance,
                rawText: "Mock remaining electricity \(roundedBalance) kWh",
                timestamp: timestamp
            ))
        }

        return records
    }
}
