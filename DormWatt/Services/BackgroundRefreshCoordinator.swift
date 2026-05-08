//
//  BackgroundRefreshCoordinator.swift
//  DormWatt
//

import Foundation
import OSLog
import WidgetKit

@MainActor
final class BackgroundRefreshCoordinator: ObservableObject {
    @Published private(set) var latestRecord: ElectricityRecord?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isRefreshing = false

    private let settingsStore: AppSettingsStore
    private let refreshManager: ElectricityRefreshManager
    private let historyStore: ElectricityHistoryStore
    private var timer: Timer?
    private var didScheduleStartupRefresh = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DormWatt",
        category: "BackgroundRefresh"
    )

    init(
        settingsStore: AppSettingsStore,
        refreshManager: ElectricityRefreshManager,
        historyStore: ElectricityHistoryStore
    ) {
        self.settingsStore = settingsStore
        self.refreshManager = refreshManager
        self.historyStore = historyStore
    }

    func start() {
        configureTimer()
        refreshIfNeededOnStartup()
    }

    func reloadConfiguration() {
        configureTimer()
    }

    func refreshNow() async {
        await refresh(trigger: "manual")
        configureTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = nil

        let settings = settingsStore.load()
        guard settings.backgroundRefreshEnabled else {
            statusMessage = "Background refresh is off."
            logger.info("Background refresh disabled")
            return
        }

        let interval = TimeInterval(max(15, settings.refreshIntervalMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh(trigger: "timer")
            }
        }
        timer?.tolerance = min(interval * 0.1, 60)

        statusMessage = "Background refresh every \(settings.refreshIntervalMinutes) min."
        logger.info("Background refresh scheduled every \(settings.refreshIntervalMinutes, privacy: .public) min")
    }

    private func refreshIfNeededOnStartup() {
        guard !didScheduleStartupRefresh else {
            return
        }
        didScheduleStartupRefresh = true

        let settings = settingsStore.load()
        guard settings.backgroundRefreshEnabled else {
            return
        }

        let latestRecord = refreshManager.latestRecord() ?? historyStore.latestRecord()
        guard shouldRefreshOnStartup(latestRecord: latestRecord, settings: settings) else {
            WidgetCenter.shared.reloadTimelines(ofKind: DormWattSharedConfiguration.widgetKind)
            return
        }

        Task { @MainActor [weak self] in
            await self?.refresh(trigger: "startup")
        }
    }

    private func shouldRefreshOnStartup(latestRecord: ElectricityRecord?, settings: AppSettings) -> Bool {
        guard let latestRecord else {
            return true
        }

        let refreshInterval = TimeInterval(max(15, settings.refreshIntervalMinutes) * 60)
        return Date().timeIntervalSince(latestRecord.timestamp) >= refreshInterval
    }

    private func refresh(trigger: String) async {
        guard !isRefreshing else {
            return
        }

        let settings = settingsStore.load()
        guard settings.backgroundRefreshEnabled else {
            statusMessage = "Background refresh is off."
            return
        }

        isRefreshing = true
        logger.info("Background refresh started: \(trigger, privacy: .public)")

        do {
            let record = try await refreshManager.refresh(
                logDidAppend: { [logger] message in
                    logger.debug("\(message, privacy: .public)")
                }
            )
            try historyStore.saveRecord(record)
            latestRecord = record
            statusMessage = "Background refreshed \(record.timestamp.formatted(date: .omitted, time: .shortened))."
            WidgetCenter.shared.reloadTimelines(ofKind: DormWattSharedConfiguration.widgetKind)
            logger.info("Background refresh succeeded. balance=\(record.balance, privacy: .public)")
        } catch {
            statusMessage = error.localizedDescription
            WidgetCenter.shared.reloadTimelines(ofKind: DormWattSharedConfiguration.widgetKind)
            logger.error("Background refresh failed: \(error.localizedDescription, privacy: .public)")
        }

        isRefreshing = false
    }
}
