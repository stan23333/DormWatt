//
//  DashboardViewModel.swift
//  DormWatt
//

import Foundation
import WidgetKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var records: [ElectricityRecord] = []
    @Published private(set) var latestRecord: ElectricityRecord?
    @Published private(set) var state: CollectorState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var debugLog = ""
    @Published var selectedRange: ElectricityTimeRange = .lastDay

    private let dataProvider: ElectricityDataProvider
    private let settingsStore: AppSettingsStore
    private var refreshTimer: Timer?

    init(
        dataProvider: ElectricityDataProvider = MockElectricityDataProvider(),
        settingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        self.dataProvider = dataProvider
        self.settingsStore = settingsStore
    }

    deinit {
        refreshTimer?.invalidate()
    }

    var lowBalanceThreshold: Double {
        settingsStore.load().lowBalanceThreshold
    }

    var refreshIntervalMinutes: Int {
        settingsStore.load().refreshIntervalMinutes
    }

    var chartRecords: [ElectricityRecord] {
        ElectricityAnalytics.records(in: selectedRange, from: records)
    }

    var isLowBalance: Bool {
        ElectricityAnalytics.isLowBalance(record: latestRecord, threshold: lowBalanceThreshold)
    }

    var selectedRangeConsumption: Double {
        ElectricityAnalytics.consumption(in: selectedRange, from: records)
    }

    func consumption(for range: ElectricityTimeRange) -> Double {
        ElectricityAnalytics.consumption(in: range, from: records)
    }

    func load() async {
        guard records.isEmpty else {
            return
        }

        do {
            let loadedRecords = try await dataProvider.loadHistory()
            apply(records: loadedRecords)
            state = .success
            appendLog("Loaded \(loadedRecords.count) history records.")
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            state = .failure(message)
            appendLog("History load failed: \(message)")
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        errorMessage = nil
        state = .loadingLoginPage
        appendLog("Refresh started.")

        do {
            let record = try await dataProvider.refresh()
            var updatedRecords = records
            updatedRecords.removeAll { $0.timestamp == record.timestamp }
            updatedRecords.append(record)
            apply(records: updatedRecords)
            WidgetCenter.shared.reloadTimelines(ofKind: DormWattSharedConfiguration.widgetKind)
            state = .success
            appendLog("Refresh succeeded. balance=\(record.balance)")
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            state = .failure(message)
            appendLog("Refresh failed: \(message)")
        }

        isRefreshing = false
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(1, refreshIntervalMinutes) * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func clearCachedData() {
        records = []
        latestRecord = nil
        errorMessage = nil
        state = .idle
        WidgetCenter.shared.reloadTimelines(ofKind: DormWattSharedConfiguration.widgetKind)
        appendLog("Cached electricity data cleared.")
    }

    func applyBackgroundRecord(_ record: ElectricityRecord) {
        var updatedRecords = records
        updatedRecords.removeAll { $0.timestamp == record.timestamp }
        updatedRecords.append(record)
        apply(records: updatedRecords)
        errorMessage = nil
        state = .success
        WidgetCenter.shared.reloadTimelines(ofKind: DormWattSharedConfiguration.widgetKind)
        appendLog("Background refresh applied. balance=\(record.balance)")
    }

    private func apply(records newRecords: [ElectricityRecord]) {
        let sortedRecords = ElectricityAnalytics.sorted(newRecords)
        records = sortedRecords
        latestRecord = sortedRecords.last
    }

    private func appendLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        debugLog += "[\(timestamp)] \(message)\n"
    }
}
