//
//  ElectricityDataProvider.swift
//  DormWatt
//

import Foundation

protocol ElectricityDataProvider {
    @MainActor
    func loadHistory() async throws -> [ElectricityRecord]
    @MainActor
    func refresh() async throws -> ElectricityRecord
}

final class MockElectricityDataProvider: ElectricityDataProvider {
    private let historyStore: ElectricityHistoryStore
    private let calendar: Calendar

    init(
        historyStore: ElectricityHistoryStore = ElectricityHistoryStore(),
        calendar: Calendar = .current
    ) {
        self.historyStore = historyStore
        self.calendar = calendar
    }

    @MainActor
    func loadHistory() async throws -> [ElectricityRecord] {
        let records = historyStore.loadRecords()
        if !records.isEmpty {
            return records
        }

        let mockRecords = ElectricityAnalytics.mockRecords(now: Date(), calendar: calendar)
        try historyStore.replaceRecords(mockRecords)
        return mockRecords
    }

    @MainActor
    func refresh() async throws -> ElectricityRecord {
        var records = try await loadHistory()
        let now = Date()
        let latest = records.last
        let baseBalance = latest?.balance ?? 18.0
        let newBalance = max(0, baseBalance - 0.05)
        let roundedBalance = (newBalance * 100).rounded() / 100
        let record = ElectricityRecord(
            balance: roundedBalance,
            rawText: "Mock remaining electricity \(roundedBalance) kWh",
            timestamp: now
        )
        records.append(record)
        try historyStore.replaceRecords(records)
        return record
    }
}

final class CollectorElectricityDataProvider: ElectricityDataProvider {
    private let refreshManager: ElectricityRefreshManager
    private let historyStore: ElectricityHistoryStore
    private let stateDidChange: ((CollectorState) -> Void)?
    private let logDidAppend: ((String) -> Void)?

    init(
        refreshManager: ElectricityRefreshManager,
        historyStore: ElectricityHistoryStore = ElectricityHistoryStore(),
        stateDidChange: ((CollectorState) -> Void)? = nil,
        logDidAppend: ((String) -> Void)? = nil
    ) {
        self.refreshManager = refreshManager
        self.historyStore = historyStore
        self.stateDidChange = stateDidChange
        self.logDidAppend = logDidAppend
    }

    @MainActor
    func loadHistory() async throws -> [ElectricityRecord] {
        historyStore.loadRecords()
    }

    @MainActor
    func refresh() async throws -> ElectricityRecord {
        let record = try await refreshManager.refresh(
            stateDidChange: stateDidChange,
            logDidAppend: logDidAppend
        )
        try historyStore.saveRecord(record)
        return record
    }
}
